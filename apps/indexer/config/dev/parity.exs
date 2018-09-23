use Mix.Config

config :indexer,
  block_interval: 5_000,
  json_rpc_named_arguments: [
    transport: EthereumJSONRPC.HTTP,
    transport_options: [
      http: EthereumJSONRPC.HTTP.HTTPoison,
      url: "http://localhost:8545",
      method_to_url: [
        eth_getBalance: "http://localhost:8545",
        trace_replayTransaction: "http://localhost:8545"
      ],
      http_options: [recv_timeout: 60_000, timeout: 60_000, hackney: [pool: :ethereum_jsonrpc]]
    ],
    variant: EthereumJSONRPC.Parity
  ],
  subscribe_named_arguments: [
    transport: EthereumJSONRPC.WebSocket,
    transport_options: [
      web_socket: EthereumJSONRPC.WebSocket.WebSocketClient,
      url: "ws://localhost:8546"
    ]
  ]
