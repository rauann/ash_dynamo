import Config

config :ash, policies: [show_policy_breakdowns?: true]

config :ex_aws, debug_requests: false

config :ex_aws,
  access_key_id: "accesskeyid",
  secret_access_key: "secretaccesskey"

config :ex_aws, :dynamodb,
  scheme: "http://",
  host: "localhost",
  port: 8088,
  region: "eu-west-1"

config :mix_test_watch, clear: true
