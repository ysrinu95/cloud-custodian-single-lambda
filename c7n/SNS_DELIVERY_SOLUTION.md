# Cloud Custodian Mailer SNS Delivery - Solution

## Problem Statement

The current implementation attempts to monkey-patch c7n-mailer to support SNS delivery with template rendering. However, this approach is:
- ❌ Trying to import non-existent `ses_delivery` module (causing ImportError)
- ❌ Unnecessarily complex with custom monkey-patching code
- ❌ Not leveraging c7n-mailer's native capabilities

## Discovery

**c7n-mailer NATIVELY supports SNS topic delivery!**

From the official documentation (https://cloudcustodian.io/docs/tools/c7n-mailer.html):

> The `to` list specifies the intended recipient for the email. **You can specify either an email address, an SNS topic**, a Datadog Metric, or a special value.

The downloaded Lambda ZIP confirms this:
```
c7n_mailer/sns_delivery.py (5,422 bytes) ✅ EXISTS
c7n_mailer/email_delivery.py (13,182 bytes) ✅ EXISTS  
c7n_mailer/ses_delivery.py ❌ DOES NOT EXIST
```

## How c7n-mailer Native SNS Delivery Works

### Architecture Flow:

```
Cloud Custodian Policy Execution
         ↓
    (SQS Queue)
         ↓
 c7n-mailer Lambda
         ↓
  [Reads SQS message]
         ↓
  [Renders Jinja2 template with resource data]
         ↓
  [Detects SNS topic ARN in "to" field]
         ↓
  [Uses sns_delivery.py module]
         ↓
  [Publishes FORMATTED HTML to SNS topic]
         ↓
    SNS Topic
         ↓
  Email Subscribers receive formatted notification
```

### Key Points:

1. **Template rendering happens BEFORE SNS publish** - c7n-mailer renders the Jinja2 template and publishes the HTML to SNS
2. **No SES required** - SNS topic handles email distribution to subscribers
3. **No monkey-patching needed** - native `sns_delivery.py` module handles everything

## The Solution

### Step 1: Update Cloud Custodian Policies

**BEFORE (incorrect - sends to email):**
```yaml
actions:
  - type: notify
    template: default.html
    subject: "Security Alert"
    to:
      - ysrinu95@gmail.com  # ❌ Direct email
    transport:
      type: sqs
      queue: https://sqs.us-east-1.amazonaws.com/172327596604/custodian-mailer-queue
```

**AFTER (correct - sends to SNS topic):**
```yaml
actions:
  - type: notify
    template: default.html
    subject: "Security Alert"
    to:
      - arn:aws:sns:us-east-1:172327596604:custodian-mailer-notifications  # ✅ SNS topic ARN
    transport:
      type: sqs
      queue: https://sqs.us-east-1.amazonaws.com/172327596604/custodian-mailer-queue
```

### Step 2: Remove Monkey-Patching Code from Terraform

**In `cloud-custodian.tf` (lines 1647-1720):**

DELETE the entire monkey-patching section that tries to import `ses_delivery` and create custom `SNSDelivery` class.

The Lambda handler should be simplified to just call the native c7n-mailer:

```python
def handler(event, context):
    """
    Cloud Custodian Mailer Lambda Handler
    Uses native c7n-mailer with SNS delivery support
    """
    import logging
    from c7n_mailer.handle import start_c7n_mailer
    
    logger = logging.getLogger()
    logger.setLevel(logging.INFO)
    
    logger.info("Starting c7n-mailer with native SNS delivery")
    start_c7n_mailer(logger, parallel=False)
    
    return {
        'statusCode': 200,
        'body': 'Mailer execution completed'
    }
```

### Step 3: Update c7n-mailer Configuration

The `config.json` embedded in the Lambda build already supports SNS - no changes needed!

c7n-mailer automatically detects SNS topic ARNs in the `to` field and uses the native `sns_delivery.py` module.

## Code Review from Downloaded Lambda ZIP

### `c7n_mailer/sns_delivery.py` (Native Module)

Key methods:
- `get_sns_message_packages()` - Renders Jinja2 templates for each resource
- `get_sns_message_package()` - Calls `get_rendered_jinja()` to render HTML template
- `deliver_sns_message()` - Publishes formatted message to SNS topic using `sns.publish()`

**Critical code snippet:**
```python
def get_sns_message_package(self, sqs_message, policy_sns_address, subject, resources):
    # THIS IS WHERE TEMPLATE RENDERING HAPPENS!
    rendered_jinja_body = get_rendered_jinja(
        policy_sns_address,
        sqs_message,
        resources,
        self.logger,
        "template",
        "default",
        self.config["templates_folders"],
    )
    return {
        "topic": policy_sns_address, 
        "subject": subject, 
        "sns_message": rendered_jinja_body  # ← Formatted HTML
    }

def deliver_sns_message(self, topic, subject, rendered_jinja_body, sqs_message):
    # Publishes the ALREADY-RENDERED HTML to SNS
    sns.publish(
        TopicArn=topic, 
        Subject=subject, 
        Message=rendered_jinja_body  # ← This is the formatted HTML!
    )
```

### Template Rendering Process

The `get_rendered_jinja()` function (from `c7n_mailer/utils.py`):
1. Loads the Jinja2 template from `msg-templates/` directory
2. Injects variables: `resources`, `account`, `region`, `policy`, `action`, etc.
3. Renders the template to HTML string
4. Returns the formatted HTML

**This happens BEFORE the SNS publish operation!**

## Benefits of Native SNS Delivery

1. ✅ **No custom code** - uses battle-tested c7n-mailer modules
2. ✅ **Template rendering preserved** - Jinja2 templates work perfectly
3. ✅ **Cross-account support** - native SNS delivery supports `cross_accounts` config
4. ✅ **Error handling** - built-in retry logic and logging
5. ✅ **Maintainable** - no monkey-patching to break on c7n-mailer updates
6. ✅ **Documented** - official Cloud Custodian feature

## Testing Strategy

1. Update test policy to use SNS topic ARN:
   ```yaml
   to:
     - arn:aws:sns:us-east-1:172327596604:custodian-mailer-notifications
   ```

2. Remove monkey-patching code from Terraform

3. Redeploy mailer Lambda

4. Run test policy:
   ```bash
   custodian run -c test-mailer-notification.yml -s output/
   ```

5. Verify:
   - SQS queue receives message ✅
   - Mailer Lambda processes message ✅
   - SNS topic receives formatted HTML ✅
   - Email subscribers receive formatted notification ✅

## References

- **Official Documentation**: https://cloudcustodian.io/docs/tools/c7n-mailer.html
- **Native SNS Module**: `c7n_mailer/sns_delivery.py` (5,422 bytes in Lambda ZIP)
- **Template Rendering**: `c7n_mailer/utils.py` - `get_rendered_jinja()` function
- **Jinja2 Templates**: `msg-templates/default.html.j2` (10,038 bytes in Lambda ZIP)

## Conclusion

The solution is **dramatically simpler** than the monkey-patching approach:

**Current (broken):** Cloud Custodian → SQS → Mailer (tries to monkey-patch) → ❌ ImportError

**Correct (native):** Cloud Custodian → SQS → Mailer (native SNS delivery) → SNS Topic → ✅ Formatted Email

**Action Required:**
1. Update all Cloud Custodian policies to use SNS topic ARN in `to` field
2. Remove monkey-patching code from `cloud-custodian.tf` (lines 1647-1720)
3. Simplify Lambda handler to just call `start_c7n_mailer()`
4. Redeploy and test

No other changes needed - c7n-mailer handles everything natively! 🎉
