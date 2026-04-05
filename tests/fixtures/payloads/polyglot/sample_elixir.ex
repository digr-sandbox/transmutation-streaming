defmodule Transmutation.Worker do
  use GenServer
  @doc "Initializes the worker"
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def handle_cast({:process, data}, state) do
    IO.inspect(data, label: "Elixir Process")
    {:noreply, state}
  end
end