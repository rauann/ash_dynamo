# Used by "mix format"
spark_locals_without_parens = [
  global_secondary_indexes: 1,
  local_secondary_indexes: 1,
  partition_key: 1,
  sort_key: 1,
  table: 1
]

[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  plugins: [Spark.Formatter],
  export_locals_without_parens: spark_locals_without_parens,
  locals_without_parens: spark_locals_without_parens,
  import_deps: [:ash, :reactor]
]
