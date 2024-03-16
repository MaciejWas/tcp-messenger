{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE NamedFieldPuns #-}

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
import TcpMsg.Effects.Connection
  ( ConnectionActions (ConnectionActions),
    ConnectionHandle (ConnectionHandle),
    ConnectionHandleRef,
    ConnectionInfo (ConnectionInfo),
    Conn,
    mkConnectionActions, runConnection,
  )
import TcpMsg.Effects.Supplier (nextConnection, eachConnectionDo)

import TcpMsg.Data (mkMsg, Header (Header), UnixMsgTime)
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

import TcpMsg.Effects.Connection (readBytes, writeBytes)
import TcpMsg.Parsing (parseMsg, parseHeader)
import TcpMsg.Server.Tcp (runTcpServer, defaultServerOpts, runTcpClient,ServerOpts(ServerOpts), ClientOpts (ClientOpts, serverHost, serverPort), ServerHandle (ServerHandle, kill), ServerOpts (port))
import Control.Monad (void)
import Network.Socket (Socket)

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
  mkConnectionActions connHandleRef mockConnStreamRead mockConnStreamWrite mockConnStreamFinalize
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

    mockConnStreamFinalize :: IO ()
    mockConnStreamFinalize = return ()

inConnectionContext ::
  forall a x.
  (Serialize a) =>
  [(UnixMsgTime, a)] ->
  Eff '[Conn MockConnStream, Concurrent, IOE] x ->
  IO x
inConnectionContext messages action =
  let inputStream = foldl (<>) mempty (map (uncurry mkMsg) messages)
      testHandle = testConnHandle inputStream
  in runEff (runConcurrent (do
    testHandleRef <- newTVarIO testHandle
    connActions <- testConnActions testHandleRef
    runConnection connActions action
  ))

--------------------------------------------------------------------------------------------------------------------------------------------------------

runServer opts action = runEff (runConcurrent (runTcpServer opts action))
runClient opts action = runEff (runConcurrent (runTcpClient opts action))

main :: IO ()
main = hspec $ do
  describe "TcpMsg" $ do
    describe "Server" $ do
      it "can start a TCP server" $ do
        (ServerHandle kill tid) <- runServer defaultServerOpts (return ())
        threadDelay 10000
        kill

      it "can start a TCP client" $ do
        let srvopts = ServerOpts { port = 4455 }
        (ServerHandle {kill}) <- runServer srvopts (return ())

        let clientopts = ClientOpts { serverHost = "localhost", serverPort = 4455 }
        runClient clientopts (return ())

        threadDelay 10000
        kill

      it "can receive connections" $ do
        let srvopts = ServerOpts { port = 4455 }
        connReceived <- newEmptyMVar

        (ServerHandle { kill }) <- runServer srvopts (do
          c <- nextConnection @Socket
          liftIO (putMVar connReceived True)
          )

        let clientopts = ClientOpts { serverHost = "localhost", serverPort = 4455  }
        runClient clientopts (void (writeBytes @Socket "AAAA"))

        connReceivedVal <- takeMVar connReceived
        connReceivedVal `shouldBe` True

        kill

      it "can receive data" $ do
        let bytes = "AAAAAAFASD FASD FASDF ASD FFF FDASF DAS"

        let srvopts = ServerOpts { port = 4455 }
        bytesReceived <- newEmptyMVar

        (ServerHandle {kill}) <- runServer srvopts (do
          eachConnectionDo @Socket (do
            bs <- readBytes @Socket (BS.length bytes)
            liftIO (putMVar bytesReceived bs)
            )
          )

        let clientopts = ClientOpts { serverHost = "localhost", serverPort = 4455  }
        runClient 
          clientopts 
          (void (writeBytes @Socket bytes))

        connReceivedVal <- takeMVar bytesReceived
        connReceivedVal `shouldBe` bytes

        kill

      it "can stop a TCP server" $ do
        let srvopts = ServerOpts { port = 4455  }
        (ServerHandle {kill=kill1}) <- runServer srvopts (return ())

        threadDelay 1000
        kill1
        threadDelay 1000

        let srvopts = ServerOpts { port = 4455  }
        (ServerHandle {kill=kill2}) <- runServer srvopts (return ())

        kill2

    describe "Data" $ do
      describe "mkMsg" $ do
        it "creates a message which contains the payload" $ do
          property $ \(messageId :: UnixMsgTime) (payload :: BS.ByteString) -> BS.isInfixOf payload (mkMsg messageId payload)

    describe "ParsingBuffers" $ do
      describe "parseMsg" $ do
        it "parses a header" $ do
          property $ \(messageId :: UnixMsgTime) (payload :: BS.ByteString)  -> monadicIO $ do
            (Header responseMsgId _) <- run (inConnectionContext [(messageId, payload)] (parseHeader @MockConnStream))
            assert (responseMsgId == messageId)

        it "parses a message" $ do
          property $ \(messageId :: UnixMsgTime) (payload :: BS.ByteString)  -> monadicIO $ do
            (Header responseMsgId _, response) <- run (inConnectionContext [(messageId, payload)] (parseMsg @MockConnStream @BS.ByteString))
            assert (response == payload)
            assert (responseMsgId == messageId)