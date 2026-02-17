defmodule AshDynamo.Test.RequestHelper do
  @moduledoc false

  @doc """
  Executes `fun` and captures the DynamoDB request body.
  Returns `{result, request_body}` where request_body is a decoded map.
  """
  def capture_dynamo_request(fun) do
    test_pid = self()
    ref = make_ref()
    handler_id = "capture-#{inspect(ref)}"

    :telemetry.attach(
      handler_id,
      [:ex_aws, :request, :start],
      &__MODULE__.handle_event/4,
      {test_pid, ref}
    )

    try do
      result = fun.()

      body =
        receive do
          {^ref, raw} -> Jason.decode!(raw)
        after
          2_000 -> raise "No ExAws request captured"
        end

      {result, body}
    after
      :telemetry.detach(handler_id)
    end
  end

  @doc """
  Executes `fun` and captures ALL DynamoDB request bodies.
  Returns `{result, [request_body]}` where each request_body is a decoded map.
  """
  def capture_all_dynamo_requests(fun) do
    test_pid = self()
    ref = make_ref()
    handler_id = "capture-all-#{inspect(ref)}"

    :telemetry.attach(
      handler_id,
      [:ex_aws, :request, :start],
      &__MODULE__.handle_event/4,
      {test_pid, ref}
    )

    try do
      result = fun.()

      bodies = drain_messages(ref, [])

      {result, bodies}
    after
      :telemetry.detach(handler_id)
    end
  end

  defp drain_messages(ref, acc) do
    receive do
      {^ref, raw} -> drain_messages(ref, [Jason.decode!(raw) | acc])
    after
      100 -> Enum.reverse(acc)
    end
  end

  def handle_event(_event, _measurements, metadata, {pid, ref}) do
    send(pid, {ref, metadata.request_body})
  end
end
