defmodule Meilisearch.Client do
  @moduledoc """
  Create a HTTP client to interact with Meilisearch APIs.
  """

  defstruct [:request]

  @type t :: %__MODULE__{request: Req.Request.t()}
  @type error :: Meilisearch.Error.t() | Exception.t() | nil

  @doc """
  Create a new HTTP client to query Meilisearch.

  ## Examples

      iex> Meilisearch.Client.new()
      %Meilisearch.Client{}

  """
  @spec new(
          endpoint: String.t(),
          key: String.t(),
          timeout: integer(),
          log_level: :info | :warn | :error
        ) :: t()
  def new(opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, "")
    key = Keyword.get(opts, :key, "")
    timeout = Keyword.get(opts, :timeout, 2_000)
    finch = Keyword.get(opts, :finch)

    headers = [
      {"content-type", "application/json"},
      {"user-agent", Meilisearch.qualified_version()}
    ]

    req_opts =
      [
        base_url: endpoint,
        headers: headers,
        receive_timeout: timeout,
        retry: false
      ]
      |> maybe_put_auth(key)
      |> maybe_put_finch(finch)

    %__MODULE__{request: Req.new(req_opts)}
  end

  @spec get(t(), String.t(), keyword()) :: {:ok, Req.Response.t()} | {:error, Exception.t()}
  def get(client, path, opts \\ []), do: request(client, :get, path, nil, opts)

  @spec post(t(), String.t(), term(), keyword()) ::
          {:ok, Req.Response.t()} | {:error, Exception.t()}
  def post(client, path, body, opts \\ []), do: request(client, :post, path, body, opts)

  @spec put(t(), String.t(), term(), keyword()) ::
          {:ok, Req.Response.t()} | {:error, Exception.t()}
  def put(client, path, body, opts \\ []), do: request(client, :put, path, body, opts)

  @spec patch(t(), String.t(), term(), keyword()) ::
          {:ok, Req.Response.t()} | {:error, Exception.t()}
  def patch(client, path, body, opts \\ []), do: request(client, :patch, path, body, opts)

  @spec delete(t(), String.t(), keyword()) :: {:ok, Req.Response.t()} | {:error, Exception.t()}
  def delete(client, path, opts \\ []), do: request(client, :delete, path, nil, opts)

  defp request(%__MODULE__{request: req}, method, path, body, opts) do
    opts =
      [
        method: method,
        url: interpolate_path_params(path, get_in(opts, [:opts, :path_params]) || []),
        params: Keyword.get(opts, :query, [])
      ]
      |> maybe_put_body(body)

    Req.request(req, opts)
  end

  @doc """
  Handles responses success and errors, returns it formatted.
  """
  @spec handle_response(term()) ::
          {:ok, map()} | {:error, Meilisearch.Error.t(), integer()} | {:error, term()}
  def handle_response({:ok, %{status: status, body: body}})
      when status in 200..299 do
    {:ok, body}
  end

  def handle_response({:ok, %{status: status, body: body}}) do
    {:error, Meilisearch.Error.cast(body), status}
  end

  def handle_response({:error, error}) do
    {:error, error}
  end

  def handle_response(_) do
    {:error, nil}
  end

  defp interpolate_path_params(path, path_params) do
    Enum.reduce(path_params, path, fn {key, value}, path ->
      String.replace(path, ":#{key}", encode_path_param(value))
    end)
  end

  defp encode_path_param(value) do
    value
    |> to_string()
    |> URI.encode(&URI.char_unreserved?/1)
  end

  defp maybe_put_body(opts, nil), do: opts
  defp maybe_put_body(opts, body) when is_binary(body), do: Keyword.put(opts, :body, body)
  defp maybe_put_body(opts, body), do: Keyword.put(opts, :json, body)

  defp maybe_put_auth(opts, ""), do: opts
  defp maybe_put_auth(opts, nil), do: opts
  defp maybe_put_auth(opts, key), do: Keyword.put(opts, :auth, {:bearer, key})

  defp maybe_put_finch(opts, nil), do: opts
  defp maybe_put_finch(opts, finch), do: Keyword.put(opts, :finch, finch)
end
