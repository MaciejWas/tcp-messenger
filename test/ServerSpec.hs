{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE DeriveGeneric #-}

module ServerSpec (serverSpec) where

import Control.Concurrent (MVar, threadDelay, newMVar, putMVar, readMVar, newEmptyMVar, takeMVar)
import Control.Exception (evaluate)
import qualified Data.ByteString as BS
import Data.Serialize (Serialize)
import qualified Data.Text as T
import Effectful
  ( Dispatch (Static),
    DispatchOf,
    Eff,
    Effect,
    IOE,
    runEff,
    (:>), MonadIO (liftIO),
  )
import Effectful.Concurrent (Concurrent, runConcurrent)
import Effectful.Concurrent.STM (STM, atomically, modifyTVar, newTVar, newTVarIO, readTVar, writeTVar, readTVarIO)
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
import Test.QuickCheck.Monadic (monadicIO, run, assert)

import Control.Monad (void)
import Network.Socket (Socket)

import Effectful.Concurrent.Async (wait)

import TcpMsg.Parsing (parseMsg, parseHeader)
import TcpMsg.Effects.Client (ask)
import TcpMsg.Effects.Logger (runLogger, noopLogger)


import TcpMsg.Server.Abstract (runServer)
import TcpMsg.Server.Tcp (runTcpConnSupplier, defaultServerTcpSettings, ServerTcpSettings(ServerTcpSettings), ServerHandle (ServerHandle, kill), ServerTcpSettings (port))

import TcpMsg.Client.Abstract (runClient)
import TcpMsg.Client.Tcp (ClientOpts (ClientOpts, serverHost, serverPort), runTcpConnection)

import TcpMsg.Effects.Connection
    ( ConnectionActions(ConnectionActions),
      ConnectionHandle(ConnectionHandle),
      ConnectionHandleRef,
      ConnectionInfo(ConnectionInfo),
      Conn,
      mkConnectionActions,
      runConnection,
      readBytes,
      writeBytes )
import TcpMsg.Effects.Supplier (nextConnection, eachConnectionDo)

import TcpMsg.Data (encodeMsg, Header (Header), UnixMsgTime, Message(Message))

--------------------------------------------------------------------------------------------------------------------------------------------------------

runTcpConnSupplier' opts action = runEff (runLogger noopLogger (runConcurrent (runTcpConnSupplier opts action)))
runTcpConnection' opts action = runEff (runLogger noopLogger (runConcurrent (runTcpConnection opts action)))

serverSpec = do
  describe "TcpMsg" $ do
    describe "Server" $ do
      it "can start a TCP server" $ do
        (ServerHandle kill tid) <- runTcpConnSupplier' defaultServerTcpSettings (return ())
        threadDelay 10000
        kill

      it "can start a TCP client" $ do
        let srvopts = ServerTcpSettings { port = 4455 }
        (ServerHandle {kill}) <- runTcpConnSupplier' srvopts (return ())

        let clientopts = ClientOpts { serverHost = "localhost", serverPort = 4455 }
        runTcpConnection' clientopts (return ())

        threadDelay 10000
        kill

      it "can receive connections" $ do
        let srvopts = ServerTcpSettings { port = 4455 }
        connReceived <- newEmptyMVar

        (ServerHandle { kill }) <- runTcpConnSupplier' srvopts (do
          c <- nextConnection @Socket
          liftIO (putMVar connReceived True)
          )

        let clientopts = ClientOpts { serverHost = "localhost", serverPort = 4455  }
        runTcpConnection' clientopts (void (writeBytes @Socket "AAAA"))

        connReceivedVal <- takeMVar connReceived
        connReceivedVal `shouldBe` True

        kill

      it "can receive data" $ do
        let bytes = "AAAAAAFASD FASD FASDF ASD FFF FDASF DAS"

        let srvopts = ServerTcpSettings { port = 4455 }
        bytesReceived <- newEmptyMVar

        (ServerHandle {kill}) <- runTcpConnSupplier' srvopts (do
          eachConnectionDo @Socket (do
            bs <- readBytes @Socket (BS.length bytes)
            liftIO (putMVar bytesReceived bs)
            )
          )

        let clientopts = ClientOpts { serverHost = "localhost", serverPort = 4455  }
        runTcpConnection'
          clientopts
          (void (writeBytes @Socket bytes))

        connReceivedVal <- takeMVar bytesReceived
        connReceivedVal `shouldBe` bytes

        kill

      it "can stop a TCP server" $ do
        let srvopts = ServerTcpSettings { port = 4455  }
        (ServerHandle {kill=kill1}) <- runTcpConnSupplier' srvopts (return ())

        threadDelay 1000
        kill1
        threadDelay 1000

        let srvopts = ServerTcpSettings { port = 4455  }
        (ServerHandle {kill=kill2}) <- runTcpConnSupplier' srvopts (return ())

        kill2