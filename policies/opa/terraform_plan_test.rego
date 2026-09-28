package terraform.guard

test_safe_plan_allowed if {
  result := deny with input as {
    "resource_changes": [
      {
        "address": "aws_ssm_parameter.release_revision",
        "type": "aws_ssm_parameter",
        "change": {
          "actions": ["update"],
          "after": {"value": "v2"}
        }
      }
    ]
  }

  count(result) == 0
}

test_delete_plan_denied if {
  result := deny with input as {
    "resource_changes": [
      {
        "address": "aws_s3_bucket.prod_state",
        "type": "aws_s3_bucket",
        "change": {
          "actions": ["delete"],
          "after": null
        }
      }
    ]
  }

  count(result) == 1
}

test_replacement_plan_denied if {
  result := deny with input as {
    "resource_changes": [
      {
        "address": "aws_db_instance.main",
        "type": "aws_db_instance",
        "change": {
          "actions": ["delete", "create"],
          "after": {"identifier": "customer-prod-db"}
        }
      }
    ]
  }

  count(result) == 1
}

test_create_before_destroy_denied if {
  result := deny with input as {
    "resource_changes": [{
      "address": "aws_ssm_parameter.release_revision",
      "type": "aws_ssm_parameter",
      "change": {"actions": ["create", "delete"], "after": {"value": "v2"}}
    }]
  }

  count(result) == 1
  some msg in result
  contains(msg, "aws_ssm_parameter.release_revision")
}

test_non_destructive_actions_allowed if {
  every actions in [["no-op"], ["read"], ["create"], ["update"]] {
    result := deny with input as {
      "resource_changes": [{
        "address": "terraform_data.example",
        "type": "terraform_data",
        "change": {"actions": actions, "after": {"input": "v1"}}
      }]
    }
    count(result) == 0
  }
}

test_complete_s3_public_access_block_allowed if {
  result := deny with input as {
    "resource_changes": [{
      "address": "aws_s3_bucket_public_access_block.secure",
      "type": "aws_s3_bucket_public_access_block",
      "change": {
        "actions": ["create"],
        "after": {
          "block_public_acls": true,
          "block_public_policy": true,
          "ignore_public_acls": true,
          "restrict_public_buckets": true
        }
      }
    }]
  }
  count(result) == 0
}

test_incomplete_s3_public_access_block_denied if {
  result := deny with input as {
    "resource_changes": [
      {
        "address": "aws_s3_bucket_public_access_block.insecure",
        "type": "aws_s3_bucket_public_access_block",
        "change": {
          "actions": ["create"],
          "after": {
            "block_public_acls": false,
            "block_public_policy": false,
            "ignore_public_acls": false,
            "restrict_public_buckets": false
          }
        }
      }
    ]
  }

  count(result) == 4
}
