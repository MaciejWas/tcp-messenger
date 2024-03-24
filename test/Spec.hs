{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE DeriveGeneric #-}

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

runTcpConnSupplier' opts action = runEff (runConcurrent (runTcpConnSupplier opts action))
runTcpConnection' opts action = runEff (runConcurrent (runTcpConnection opts action))

main :: IO ()
main = hspec $ do
  describe "TcpMsg" $ do
    describe "Client" $ do
      it "can send a bytestring trunk" $ do
        responseReceived <- newEmptyMVar
        let trunkData = "fasdfsdafasdf asdf asd fasd fdas fas fsdalllf"
        let request = (Message 42 (Just trunkData))

        -- Start a server which responds with x + 1
        let srvopts = ServerOpts { port = 4455 }
        (ServerHandle { kill }) <- runTcpConnSupplier' srvopts (do
          runServer @Int @Bool @Socket (\(Message x t) -> return (Message (t == Just trunkData) t))
          )

        -- Start a client which sends a single request
        let clientopts = ClientOpts { serverHost = "localhost", serverPort = 4455  }
        runTcpConnection' clientopts (runClient @Int @Bool @Socket (do
          response <- ask @Int @Bool @Socket request >>= wait
          liftIO (putMVar responseReceived response)
          return ()
          ))

        responseReceivedVal <- takeMVar responseReceived
        responseReceivedVal `shouldBe` Message True (Just trunkData)

        kill

      it "can receive a bytestring trunk" $ do
        responseReceived <- newEmptyMVar
        let trunkData = "fasdfsdafasdf asdf asd fasd fdas fas fsdalllf"
        let request = (Message 42 (Nothing))

        -- Start a server which responds with x + 1
        let srvopts = ServerOpts { port = 4455 }
        (ServerHandle { kill }) <- runTcpConnSupplier' srvopts (do
          runServer @Int @Bool @Socket (\(Message x t) -> return (Message True (Just trunkData)))
          )

        -- Start a client which sends a single request
        let clientopts = ClientOpts { serverHost = "localhost", serverPort = 4455  }
        runTcpConnection' clientopts (runClient @Int @Bool @Socket (do
          response <- ask @Int @Bool @Socket request >>= wait
          liftIO (putMVar responseReceived response)
          return ()
          ))

        responseReceivedVal <- takeMVar responseReceived
        responseReceivedVal `shouldBe` Message True (Just trunkData)

        kill

      it "can send a single message to a server" $ do
        responseReceived <- newEmptyMVar
        let request = (Message 42 Nothing)

        -- Start a server which responds with x + 1
        let srvopts = ServerOpts { port = 4455 }
        (ServerHandle { kill }) <- runTcpConnSupplier' srvopts (do
          runServer @Int @Int @Socket (\(Message x t) -> return (Message (x + 1) t))
          )

        -- Start a client which sends a single request
        let clientopts = ClientOpts { serverHost = "localhost", serverPort = 4455  }
        runTcpConnection' clientopts (runClient @Int @Int @Socket (do
          response <- ask @Int @Int @Socket request >>= wait
          liftIO (putMVar responseReceived response)
          return ()
          ))

        responseReceivedVal <- takeMVar responseReceived
        responseReceivedVal `shouldBe` (Message 43 Nothing)

        kill

      it "can send a multiple messages to a server" $ do
        responsesReceived <- newEmptyMVar

        let requests = map mkSomeData [1..200]
        let processRequest (Message x t) = Message x{baz=True} t

        -- Start a server which modifies the data
        let srvopts = ServerOpts { port = 4455 }
        (ServerHandle { kill }) <- runTcpConnSupplier' srvopts (do
          runServer @SomeData @SomeData @Socket (return . processRequest)
          )

        -- Start a client which sends a single request
        let clientopts = ClientOpts { serverHost = "localhost", serverPort = 4455  }
        runTcpConnection' clientopts (runClient @SomeData @SomeData @Socket (do
          futureResponses <- mapM (ask @SomeData @SomeData @Socket) requests
          responses <- mapM wait (reverse futureResponses)
          liftIO (putMVar responsesReceived responses)
          ))

        responsesReceivedVal <- takeMVar responsesReceived
        responsesReceivedVal `shouldBe` map processRequest (reverse requests)

        kill

    describe "Server" $ do
      it "can start a TCP server" $ do
        (ServerHandle kill tid) <- runTcpConnSupplier' defaultServerOpts (return ())
        threadDelay 10000
        kill

      it "can start a TCP client" $ do
        let srvopts = ServerOpts { port = 4455 }
        (ServerHandle {kill}) <- runTcpConnSupplier' srvopts (return ())

        let clientopts = ClientOpts { serverHost = "localhost", serverPort = 4455 }
        runTcpConnection' clientopts (return ())

        threadDelay 10000
        kill

      it "can receive connections" $ do
        let srvopts = ServerOpts { port = 4455 }
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

        let srvopts = ServerOpts { port = 4455 }
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
        let srvopts = ServerOpts { port = 4455  }
        (ServerHandle {kill=kill1}) <- runTcpConnSupplier' srvopts (return ())

        threadDelay 1000
        kill1
        threadDelay 1000

        let srvopts = ServerOpts { port = 4455  }
        (ServerHandle {kill=kill2}) <- runTcpConnSupplier' srvopts (return ())

        kill2

    describe "Data" $ do
      describe "encodeMsg" $ do
        it "creates a message which contains the payload" $ do
          property $ \(messageId :: UnixMsgTime) (payload :: BS.ByteString) -> BS.isInfixOf payload (encodeMsg messageId (Message payload Nothing))

    describe "ParsingBuffers" $ do
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