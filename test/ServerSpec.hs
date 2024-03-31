{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

module ServerSpec (serverSpec) where

import Control.Concurrent (forkIO, killThread, threadDelay)
import Control.Concurrent.Async (wait)
import Control.Concurrent.MVar (isEmptyMVar, newEmptyMVar, putMVar)
import Control.Monad (replicateM, void)
import qualified Control.Monad.Catch as E
import TcpMsg (ServerSettings (ServerSettings, action, tcpOpts), createClient)
import qualified TcpMsg (run)
import TcpMsg.Client.Abstract (ask)
import TcpMsg.Client.Tcp (ClientOpts (ClientOpts, serverHost, serverPort))
import TcpMsg.Data (Message (Message))
import TcpMsg.Server.Tcp (ServerTcpSettings (ServerTcpSettings, port))
import Test.Hspec
  ( describe,
    it,
    shouldBe,
  )

--------------------------------------------------------------------------------------------------------------------------------------------------------

serverSpec = do
  describe "Server" $ do
    it "can start a TCP server" $ do
      err <- newEmptyMVar

      tid <-
        forkIO
          ( void
              ( E.onError
                  (TcpMsg.run @Int @Int (ServerSettings {tcpOpts = ServerTcpSettings {port = 44551}, action = return}))
                  (putMVar err ())
              )
          )

      threadDelay 10000
      isEmptyMVar err >>= shouldBe True -- Assert that the server thread had no errors
      killThread tid

    it "can start a TCP client" $ do
      err <- newEmptyMVar

      tid <-
        forkIO
          ( void
              ( E.onError
                  (TcpMsg.run @Int @Int (ServerSettings {tcpOpts = ServerTcpSettings {port = 44551}, action = return}))
                  (putMVar err ())
              )
          )

      threadDelay 10000

      client <- TcpMsg.createClient @Int @Int (ClientOpts {serverHost = "localhost", serverPort = 44551})
      response <- client `ask` Message 1234 Nothing >>= wait

      threadDelay 10000
      isEmptyMVar err >>= shouldBe True -- Assert that the server thread had no errors
      killThread tid

      response `shouldBe` (Message 1234 Nothing) -- Assert that the server thread had no errors
    it "can handle multiple connections" $ do
      err <- newEmptyMVar

      tid <-
        forkIO
          ( void
              ( E.onError
                  (TcpMsg.run @Int @Int (ServerSettings {tcpOpts = ServerTcpSettings {port = 44551}, action = return}))
                  (putMVar err ())
              )
          )

      threadDelay 10000

      responses <-
        replicateM
          50
          ( do
              client <- TcpMsg.createClient @Int @Int (ClientOpts {serverHost = "localhost", serverPort = 44551})
              client `ask` Message 1234 Nothing
          )

      threadDelay 10000
      isEmptyMVar err >>= shouldBe True -- Assert that the server thread had no errors
      killThread tid

      mapM wait responses >>= shouldBe (replicate 50 (Message 1234 Nothing)) -- Assert that the server thread had no errors
    it "can stop a TCP server" $ do
      tid <-
        forkIO
          ( void
              ( TcpMsg.run @Int @Int (ServerSettings {tcpOpts = ServerTcpSettings {port = 44551}, action = return})
              )
          )
      threadDelay 100
      killThread tid

      tid2 <-
        forkIO
          ( void
              ( TcpMsg.run @Int @Int (ServerSettings {tcpOpts = ServerTcpSettings {port = 44551}, action = return})
              )
          )
      threadDelay 100
      killThread tid2
