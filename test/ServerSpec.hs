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

import Control.Concurrent (MVar, threadDelay, throwTo, killThread, forkIO)
import Control.Exception (evaluate, SomeException (SomeException), Exception (toException))
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
import Test.QuickCheck.Monadic (monadicIO, run, assert)

import Control.Monad (void, mapM, replicateM)
import Network.Socket (Socket)


import TcpMsg.Parsing (parseMsg, parseHeader)
import TcpMsg.Effects.Client (ask)

import TcpMsg.Server.Abstract (runServer)
import TcpMsg.Server.Tcp (defaultServerTcpSettings, ServerTcpSettings(ServerTcpSettings), ServerTcpSettings (port))

import TcpMsg.Client.Abstract (createClient)
import TcpMsg.Client.Tcp (ClientOpts (ClientOpts, serverHost, serverPort))

import TcpMsg.Effects.Connection
    ( Connection(..),
      ConnectionHandle(ConnectionHandle),
      ConnectionHandleRef,
      ConnectionInfo(ConnectionInfo),
      mkConnection,
      readBytes,
      writeBytes )
import TcpMsg.Effects.Supplier (nextConnection, eachConnectionDo)

import TcpMsg.Data (encodeMsg, Header (Header), UnixMsgTime, Message(Message))

import TcpMsg (ServerSettings(ServerSettings, tcpOpts, action), createClient)
import qualified TcpMsg (run)
import qualified Control.Monad.Catch as E
import Control.Concurrent.STM (newTMVarIO)

import Control.Concurrent.MVar (newEmptyMVar, newMVar, putMVar, readMVar, newEmptyMVar, takeMVar, isEmptyMVar)
import Control.Concurrent.Async (wait)

--------------------------------------------------------------------------------------------------------------------------------------------------------

serverSpec = do
  describe "Server" $ do
    it "can start a TCP server" $ do
      err <- newEmptyMVar

      tid <- forkIO (void (
        E.onError 
          (TcpMsg.run @Int @Int (ServerSettings{ tcpOpts=ServerTcpSettings { port = 44551 }, action=return}))
          (putMVar err ())
        ))

      threadDelay 10000
      isEmptyMVar err >>= shouldBe True -- Assert that the server thread had no errors
      killThread tid

    it "can start a TCP client" $ do
      err <- newEmptyMVar

      tid <- forkIO (void (
        E.onError 
          (TcpMsg.run @Int @Int (ServerSettings{ tcpOpts=ServerTcpSettings { port = 44551 }, action=return}))
          (putMVar err ())
        ))

      threadDelay 10000

      client <- TcpMsg.createClient @Int @Int (ClientOpts { serverHost = "localhost", serverPort = 44551  })
      response <- client `ask` Message 1234 Nothing >>= wait

      threadDelay 10000
      isEmptyMVar err >>= shouldBe True -- Assert that the server thread had no errors
      killThread tid

      response `shouldBe` (Message 1234 Nothing) -- Assert that the server thread had no errors

    it "can handle multiple connections" $ do
      err <- newEmptyMVar

      tid <- forkIO (void (
        E.onError 
          (TcpMsg.run @Int @Int (ServerSettings{ tcpOpts=ServerTcpSettings { port = 44551 }, action=return}))
          (putMVar err ())
        ))

      threadDelay 10000

      responses <- replicateM 50 (do
        client <- TcpMsg.createClient @Int @Int (ClientOpts { serverHost = "localhost", serverPort = 44551  })
        client `ask` Message 1234 Nothing
        )

      threadDelay 10000
      isEmptyMVar err >>= shouldBe True -- Assert that the server thread had no errors
      killThread tid

      mapM wait responses >>= shouldBe (replicate 50 (Message 1234 Nothing)) -- Assert that the server thread had no errors
    
    it "can stop a TCP server" $ do
      tid <- forkIO (void (
          TcpMsg.run @Int @Int (ServerSettings{ tcpOpts=ServerTcpSettings { port = 44551 }, action=return})
        ))
      threadDelay 100
      killThread tid

      tid2 <- forkIO (void (
          TcpMsg.run @Int @Int (ServerSettings{ tcpOpts=ServerTcpSettings { port = 44551 }, action=return})
        ))
      threadDelay 100
      killThread tid2
      
