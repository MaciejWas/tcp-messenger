# tcp-messenger

[![codecov](https://codecov.io/gh/MaciejWas/tcp-messenger/graph/badge.svg?token=7BSX9WFCQE)](https://codecov.io/gh/MaciejWas/tcp-messenger)
![example workflow](https://github.com/MaciejWas/tcp-messenger/actions/workflows/haskell.yml/badge.svg)

## Example
```haskell
-- Requests consist of serializable header and an optional bytestring message
let request = Message (42 :: Int) (Just "some-additional-data")

-- Start a server which responds to `x` with `x + 1`
tid <-
  forkIO
    ( void
        ( TcpMsg.run @Int @Int -- Request and response types
            ( ServerSettings
                { tcpOpts = ServerTcpSettings {port = 44551},
                  action = \(Message x bytes) -> return (Message (x + 1) bytes) -- Server processes requests in parallel
                }
            )
        )
    )

threadDelay 1000 -- wait for the server to start

-- Start a client which sends a single request
let clientOpts = ClientOpts {serverHost = "localhost", serverPort = 44551}

client <- createClient clientOpts
response <- (client `ask` request >>= wait) -- `ask` performs a non-blocking request
response `shouldBe` Message (43 :: Int) (Just "some-additional-data")
```
