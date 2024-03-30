{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}

module ClientSpec (clientSpec) where

import Control.Concurrent (MVar, forkIO, isEmptyMVar, killThread, newEmptyMVar, newMVar, putMVar, readMVar, takeMVar, threadDelay)
import Control.Concurrent.Async (wait)
import Control.Exception (evaluate)
import Control.Monad (replicateM, void, (>=>))
import qualified Control.Monad.Catch as E
import qualified Data.ByteString as BS
import Data.Serialize (Serialize)
import qualified Data.Text as T
import GHC.Base (undefined)
import GHC.Generics (Generic)
import Network.Socket (Socket)
import TcpMsg (ServerSettings (..), createClient, run)
import TcpMsg.Client.Tcp (ClientOpts (ClientOpts, serverHost, serverPort))
import TcpMsg.Data (Header (Header), Message (Message), UnixMsgTime, encodeMsg)
import TcpMsg.Effects.Client (Client (..), ask)
import TcpMsg.Effects.Connection
  ( Connection (..),
    ConnectionHandle (ConnectionHandle),
    ConnectionHandleRef,
    ConnectionInfo (ConnectionInfo),
    mkConnection,
    readBytes,
    writeBytes,
  )
import TcpMsg.Effects.Supplier (eachConnectionDo, nextConnection)
import TcpMsg.Parsing (parseHeader, parseMsg)
import TcpMsg.Server.Abstract (runServer)
import TcpMsg.Server.Tcp (ServerTcpSettings (ServerTcpSettings, port), defaultServerTcpSettings)
import Test.Hspec
  ( anyException,
    describe,
    hspec,
    it,
    shouldBe,
    shouldThrow,
  )
import Test.QuickCheck (Testable (property))
import Test.QuickCheck.Instances.ByteString
import Test.QuickCheck.Monadic (assert, monadicIO)

--------------------------------------------------------------------------------------------------------------------------------------------------------

data SomeData = SomeData
  { foo :: String,
    bar :: [Int],
    baz :: Bool
  }
  deriving (Generic, Show, Eq)

instance Serialize SomeData

mkSomeData :: Int -> Message SomeData
mkSomeData i =
  Message
    SomeData {foo = show (i * 100), bar = [i .. (i + 30)], baz = False}
    Nothing

--------------------------------------------------------------------------------------------------------------------------------------------------------

clientSpec = do
  describe "Client" $ do
    it "can send a bytestring trunk" $ do
      let trunkData = "fasdfsdafasdf asdf asd fasd fdas fas fsdalllf fasdf asd"
      let request = Message (42 :: Int) (Just trunkData)

      tid <-
        forkIO
          ( void
              ( TcpMsg.run @Int @Bool
                  ( ServerSettings
                      { tcpOpts = ServerTcpSettings {port = 44551},
                        action = \(Message x t) -> return (Message (t == Just trunkData) t)
                      }
                  )
              )
          )

      threadDelay 1000

      let clientopts = ClientOpts {serverHost = "localhost", serverPort = 44551}
      client <- createClient clientopts
      response <- (client `ask` request) >>= wait
      response `shouldBe` Message True (Just trunkData)

      killThread tid
      threadDelay 100

    it "can send a single message to a server" $ do
      responseReceived <- newEmptyMVar
      let request = Message (42 :: Int) Nothing

      -- Start a server which responds with x + 1
      tid <-
        forkIO
          ( void
              ( TcpMsg.run @Int @Int
                  ( ServerSettings
                      { tcpOpts = ServerTcpSettings {port = 44551},
                        action = \(Message x t) -> return (Message (x + 1) t)
                      }
                  )
              )
          )

      threadDelay 1000

      -- Start a client which sends a single request
      let clientOpts = ClientOpts {serverHost = "localhost", serverPort = 44551}
      client <- createClient clientOpts
      response <- (client `ask` request) >>= wait
      response `shouldBe` (Message (43 :: Int) Nothing)

      killThread tid

    it "can send a multiple messages to a server" $ do
      let requests = map mkSomeData [1 .. 200]
      let processRequest (Message x t) = Message x {baz = True} t

      -- Start a server which modifies the data
      tid <-
        forkIO
          ( void
              ( TcpMsg.run @SomeData @SomeData
                  ( ServerSettings
                      { tcpOpts = ServerTcpSettings {port = 44551},
                        action = return . processRequest
                      }
                  )
              )
          )

      threadDelay 1000

      -- Start a client which sends a single request
      let clientopts = ClientOpts {serverHost = "localhost", serverPort = 44551}
      client <- createClient clientopts
      responses <- mapM (ask client >=> wait) requests

      responses `shouldBe` map processRequest requests

      killThread tid
