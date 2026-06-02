defmodule MeilisearchTest.MeiliContainer do
  @moduledoc """
  Functions to run and interact with Meilisearch containers.
  """

  @port 7700
  @wait_attempts 60
  @wait_interval 500

  @doc """
  Starts a Meilisearch container.
  """
  def start(image, opts \\ []) do
    key = Keyword.get(opts, :key, "master_test_key")

    with {:ok, container_id} <-
           docker(
             [
               "run",
               "--rm",
               "--detach",
               "--publish",
               "127.0.0.1::#{@port}",
               "--env",
               "MEILI_MASTER_KEY=#{key}",
               image
             ],
             trim: true
           ),
         {:ok, _} <- wait_until_available(container_id) do
      {:ok, container_id}
    end
  end

  @doc """
  Stops a Meilisearch container.
  """
  def stop(container_id) do
    docker(["stop", container_id])
    :ok
  end

  @doc """
  Returns the port on the _host machine_ where the Meilisearch container is listening.
  """
  def port(container_id) do
    with {:ok, port_mapping} <- docker(["port", container_id, "#{@port}/tcp"], trim: true),
         {:ok, port} <- parse_port(port_mapping) do
      {:ok, port}
    end
  end

  @doc """
  Returns the endpoint of Meilisearch from the the _host machine_ pov.
  """
  def connection_url(container_id) do
    with {:ok, port} <- port(container_id) do
      {:ok, "http://localhost:#{port}/"}
    end
  end

  defp wait_until_available(container_id, attempt \\ 1)

  defp wait_until_available(container_id, attempt) when attempt <= @wait_attempts do
    case connection_url(container_id) do
      {:ok, url} ->
        case Req.get(url <> "health", retry: false, receive_timeout: 1_000) do
          {:ok, %{status: 200, body: %{"status" => "available"}}} ->
            {:ok, container_id}

          _ ->
            Process.sleep(@wait_interval)
            wait_until_available(container_id, attempt + 1)
        end

      {:error, _} ->
        Process.sleep(@wait_interval)
        wait_until_available(container_id, attempt + 1)
    end
  end

  defp wait_until_available(container_id, _attempt) do
    stop(container_id)
    {:error, :meilisearch_container_not_available}
  end

  defp docker(args, opts \\ []) do
    case System.cmd("docker", args, stderr_to_stdout: true) do
      {output, 0} ->
        output =
          if Keyword.get(opts, :trim, false) do
            String.trim(output)
          else
            output
          end

        {:ok, output}

      {output, exit_status} ->
        {:error, {:docker, exit_status, output}}
    end
  end

  defp parse_port(port_mapping) do
    port_mapping
    |> String.split("\n", trim: true)
    |> Enum.find_value(fn mapping ->
      case Regex.run(~r/:(\d+)$/, mapping) do
        [_, port] -> {:ok, String.to_integer(port)}
        _ -> nil
      end
    end)
    |> case do
      nil -> {:error, {:docker_port, port_mapping}}
      result -> result
    end
  end
end
