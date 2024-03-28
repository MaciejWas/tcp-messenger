{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE DeriveGeneric #-}

module ClientSpec (clientSpec) where

import Control.Concurrent (MVar, threadDelay, newMVar, putMVar, readMVar, newEmptyMVar, takeMVar)
import Control.Exception (evaluate)
import qualified Data.ByteString as BS
import Data.Serialize (Serialize)
import qualified Data.Text as T

import GHC.Base (undefined)
import GHC.Generics (Generic)
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
import Test.QuickCheck.Monadic (monadicIO, assert)

import Control.Monad (void)
import Network.Socket (Socket)

import TcpMsg.Parsing (parseMsg, parseHeader)
import TcpMsg.Effects.Client (Client(..), ask)
import TcpMsg (ServerSettings(..), run, createClient)

import TcpMsg.Server.Abstract (runServer)
import TcpMsg.Server.Tcp (defaultServerTcpSettings, ServerTcpSettings(ServerTcpSettings), ServerTcpSettings (port))

import TcpMsg.Client.Tcp (ClientOpts (ClientOpts, serverHost, serverPort))

import TcpMsg.Effects.Connection
    ( ConnectionHandle(ConnectionHandle),
      ConnectionHandleRef,
      ConnectionInfo(ConnectionInfo),
      Connection(..),
      mkConnection,
      readBytes,
      writeBytes )
import TcpMsg.Effects.Supplier (nextConnection, eachConnectionDo)

import TcpMsg.Data (encodeMsg, Header (Header), UnixMsgTime, Message(Message))

--------------------------------------------------------------------------------------------------------------------------------------------------------

data SomeData = SomeData {
  foo :: String,
  bar :: [Int],
  baz :: Bool
} deriving (Generic, Show, Eq)

instance Serialize SomeData

mkSomeData :: Int -> Message SomeData
mkSomeData i
 = Message
    SomeData { foo = show (i * 100), bar = [i..(i+30)], baz = False}
    Nothing

--------------------------------------------------------------------------------------------------------------------------------------------------------

clientSpec = do
  describe "TcpMsg" $ do
    describe "Client" $ do
      return ()
      -- it "can send a bytestring trunk" $ do
      --   responseReceived <- newEmptyMVar
      --   let trunkData = "fasdfsdafasdf asdf asd fasd fdas fas fsdalllf fasdf asd"
      --   let request = (Message 42 (Just trunkData))

      --   run @Int @Bool
      --     (ServerSettings {
      --       tcpOpts = ServerTcpSettings { port = 4455 },
      --       action = \(Message x t) -> return (Message (t == Just trunkData) t)
      --       })

      --   -- Start a client which sends a single request
      --   let clientopts = ClientOpts { serverHost = "localhost", serverPort = 4455  }
      --   client <- createClient clientopts
      --   response <- (client `ask` request) >>= wait

      --   responseReceivedVal <- takeMVar responseReceived
      --   responseReceivedVal `shouldBe` Message True (Just trunkData)

      -- it "can receive a bytestring trunk" $ do
      --   responseReceived <- newEmptyMVar
      --   let trunkData = "fasdfsdafasdf asdf asd fasd fdas fas fsdalllf"
      --   let request = Message 42 Nothing

      --   -- Run the server
      --   run
      --     (ServerSettings {
      --       tcpOpts = ServerTcpSettings { port = 4455 },
      --       action = \(Message x t) -> return (Message True (Just trunkData))
      --       })

      --   -- Start a client which sends a single request
      --   let clientopts = ClientOpts { serverHost = "localhost", serverPort = 4455  }
      --   client <- createClient clientOpts
      --   response <- (client `ask` request) >>= wait

      --   response `shouldBe` Message True (Just trunkData)

      -- it "can send a single message to a server" $ do
      --   responseReceived <- newEmptyMVar
      --   let request = Message 42 Nothing

      --   -- Start a server which responds with x + 1
      --   run
      --     (ServerSettings {
      --       tcpOpts = ServerTcpSettings { port = 4455 },
      --       action = \(Message x t) -> return (Message (x + 1) t)
      --       })

      --   -- Start a client which sends a single request
      --   let clientopts = ClientOpts { serverHost = "localhost", serverPort = 4455  }
      --   client <- createClient clientOpts
      --   response <- (client `ask` request) >>= wait
      --   response `shouldBe` (Message 43 Nothing)

      -- it "can send a multiple messages to a server" $ do
      --   responsesReceived <- newEmptyMVar

      --   let requests = map mkSomeData [1..200]
      --   let processRequest (Message x t) = Message x{baz=True} t

      --   -- Start a server which modifies the data
      --   run
      --     (ServerSettings {
      --       tcpOpts = ServerTcpSettings { port = 4455 },
      --       action = return . processRequest
      --       })

      --   -- Start a client which sends a single request
      --   let clientopts = ClientOpts { serverHost = "localhost", serverPort = 4455  }
      --   client <- createClient clientopts
      --   responses <- mapM wait (reverse futureResponses)

      --   responses `shouldBe` map processRequest (reverse requests)
