{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE DeriveGeneric #-}

module ParserSpec (parserSpec) where

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
import TcpMsg.Server.Tcp (runTcpConnSupplier, defaultServerOpts, ServerOpts(ServerOpts), ServerHandle (ServerHandle, kill), ServerOpts (port))

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

data MockConnStream
  = MockConnStream
      BS.StrictByteString -- input
      BS.StrictByteString -- output

testConnHandle :: BS.StrictByteString -> ConnectionHandle MockConnStream
testConnHandle input = ConnectionHandle (ConnectionInfo mempty) (MockConnStream input mempty)

testConnActions ::
  forall es.
  (Concurrent :> es) =>
  ConnectionHandleRef MockConnStream ->
  Eff es (ConnectionActions MockConnStream)
testConnActions connHandleRef = do
  mkConnectionActions connHandleRef mockConnStreamRead mockConnStreamWrite
  where
    mockConnStreamWrite :: BS.StrictByteString -> IO ()
    mockConnStreamWrite bytes = runEff (runConcurrent (atomically go))
      where
        go :: STM ()
        go = modifyTVar connHandleRef (\(ConnectionHandle info (MockConnStream inp outp)) -> ConnectionHandle info (MockConnStream inp (outp <> bytes)))

    mockConnStreamRead :: Int -> IO BS.StrictByteString
    mockConnStreamRead size = runEff (runConcurrent (atomically go))
      where
        go :: STM BS.StrictByteString
        go = do
          (ConnectionHandle info (MockConnStream inp outp)) <- readTVar connHandleRef
          let (read, remain) = BS.splitAt size inp
          writeTVar connHandleRef (ConnectionHandle info (MockConnStream remain outp))
          return read

inConnectionContext ::
  forall a x.
  (Serialize a) =>
  [(UnixMsgTime, Message a)] ->
  Eff '[Conn MockConnStream, Concurrent, IOE] x ->
  IO x
inConnectionContext messages action =
  let inputStream = foldl (<>) mempty (map (uncurry encodeMsg) messages)
      testHandle = testConnHandle inputStream
  in runEff (runConcurrent (do
    testHandleRef <- newTVarIO testHandle
    connActions <- testConnActions testHandleRef
    runConnection connActions action
  ))

--------------------------------------------------------------------------------------------------------------------------------------------------------


parserSpec = do
  describe "TcpMsg" $ do
    describe "Data" $ do
      describe "encodeMsg" $ do
        it "creates a message which contains the payload" $ do
          property $ \(messageId :: UnixMsgTime) (payload :: BS.ByteString) -> BS.isInfixOf payload (encodeMsg messageId (Message payload Nothing))

    describe "Parsing" $ do
      describe "parseMsg" $ do
        it "parses a header" $ do
          property $ \(messageId :: UnixMsgTime) (payload :: BS.ByteString)  -> monadicIO $ do
            (Header responseMsgId _ _) <- run (inConnectionContext [(messageId, Message payload Nothing)] (parseHeader @MockConnStream))
            assert (responseMsgId == messageId)

        it "parses a message" $ do
          property $ \(messageId :: UnixMsgTime) (payload :: BS.ByteString)  -> monadicIO $ do
            (Header responseMsgId _ _, Message response _) <- run (inConnectionContext [(messageId, Message payload Nothing)] (parseMsg @MockConnStream @BS.ByteString))
            assert (response == payload)
            assert (responseMsgId == messageId)