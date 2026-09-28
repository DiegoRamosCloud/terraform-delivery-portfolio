package terraform.guard

deny contains msg if {
  change := input.resource_changes[_]
  "delete" in change.change.actions
  msg := sprintf("acao destrutiva %v bloqueada para %s porque inclui delete", [change.change.actions, change.address])
}

deny contains msg if {
  change := input.resource_changes[_]
  change.type == "aws_s3_bucket_public_access_block"
  after := change.change.after
  after.block_public_acls != true
  msg := sprintf("S3 public access block incompleto em %s: block_public_acls deve ser true", [change.address])
}

deny contains msg if {
  change := input.resource_changes[_]
  change.type == "aws_s3_bucket_public_access_block"
  after := change.change.after
  after.block_public_policy != true
  msg := sprintf("S3 public access block incompleto em %s: block_public_policy deve ser true", [change.address])
}

deny contains msg if {
  change := input.resource_changes[_]
  change.type == "aws_s3_bucket_public_access_block"
  after := change.change.after
  after.ignore_public_acls != true
  msg := sprintf("S3 public access block incompleto em %s: ignore_public_acls deve ser true", [change.address])
}

deny contains msg if {
  change := input.resource_changes[_]
  change.type == "aws_s3_bucket_public_access_block"
  after := change.change.after
  after.restrict_public_buckets != true
  msg := sprintf("S3 public access block incompleto em %s: restrict_public_buckets deve ser true", [change.address])
}
