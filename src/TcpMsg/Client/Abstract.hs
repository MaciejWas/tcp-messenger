{-# LANGUAGE NamedFieldPuns #-}
module TcpMsg.Client.Abstract where
import Control.Concurrent (ThreadId, forkIO)

import qualified Control.Concurrent.STM as STM
import Control.Monad (forever)
import Data.Serialize (Serialize)

import qualified StmContainers.Map as M
import TcpMsg.Data (Header (Header), Message, UnixMsgTime, fromUnix)
import TcpMsg.Effects.Connection (Connection, sendMessage)
import TcpMsg.Parsing (parseMsg)
import Control.Concurrent.STM (atomically)
import qualified Data.Text as T
import qualified Network.Socket as Net
import Control.Concurrent.Async (Async, async)
import Data.UnixTime (getUnixTime)

----------------------------------------------------------------------------------------------------------

type MessageMap response =
  M.Map
    UnixMsgTime
    (STM.TMVar (Message response))

data Client a b c = Client
  { clientName :: T.Text,
    msgs :: STM.TVar (MessageMap b),
    worker :: ThreadId,
    connection :: Connection c
  }

type TcpClient a b = Client a b Net.Socket

----------------------------------------------------------------------------------------------------------

newMessageId :: IO UnixMsgTime
newMessageId = fromUnix <$> getUnixTime

-- Get a map of pending messages
pendingMessages :: Client a b c -> STM.TVar (MessageMap b)
pendingMessages = msgs

blockingWaitForResponse :: Client a b c -> UnixMsgTime -> IO (Message b)
blockingWaitForResponse client unixTime = do
  atomically
    ( do
        msgs_ <- STM.readTVar (msgs client)
        response <- M.lookup unixTime msgs_
        case response of
          Just r -> M.delete unixTime msgs_ >> STM.takeTMVar r
          Nothing -> initMessage msgs_ unixTime >>= STM.takeTMVar
    )
  where
    -- Create a new MVar which will contain the response
    initMessage ::
      MessageMap b ->
      UnixMsgTime ->
      STM.STM (STM.TMVar (Message b))
    initMessage msgs msgTime =
      do
        v <- STM.newEmptyTMVar
        M.insert v msgTime msgs
        return v

ask ::
  (Serialize a) =>
  Client a b c ->
  Message a ->
  IO (Async (Message b))
ask client@Client {connection} msg = sendRequest >>= (async . blockingWaitForResponse client)
  where
    sendRequest :: IO UnixMsgTime
    sendRequest = do
      msgId <- newMessageId
      sendMessage connection msgId msg
      return msgId

----------------------------------------------------------------------------------------------------------

notifyMessage ::
  STM.TVar (MessageMap b) ->
  (Header, Message b) ->
  IO ()
notifyMessage msgs (Header msgTime _ _, newMsg) =
  atomically
    ( do
        msgs_ <- STM.readTVar msgs
        currVar <- M.lookup msgTime msgs_
        case currVar of
          Nothing ->
            ( do
                responseMVar <- STM.newTMVar newMsg
                M.insert responseMVar msgTime msgs_ 
            )
          Just mvar -> STM.putTMVar mvar newMsg
    )

startWorker ::
  ( Serialize b) =>
  Connection c ->
  STM.TVar (MessageMap b) ->
  IO ThreadId
startWorker conn msgs =
  (forkIO . forever)
    (readNextMessage >>= notifyMessageReceived)
  where
    readNextMessage = parseMsg conn
    notifyMessageReceived = notifyMessage msgs

createClient ::
  ( Serialize b
  ) =>
  Connection c ->
  IO (Client a b c)
createClient conn = do
  msgs <- atomically (M.new >>= STM.newTVar)
  workerThreadId <- startWorker conn msgs
  return (Client mempty msgs workerThreadId conn)