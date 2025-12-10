import Config

config :ash, policies: [show_policy_breakdowns?: true]

config :ex_aws,
  access_key_id: "accesskeyid",
  secret_access_key: "secretaccesskey",
  debug_requests: true

config :ex_aws, :dynamodb,
  scheme: "http://",
  host: "localhost",
  port: 8099,
  region: "eu-west-1"
