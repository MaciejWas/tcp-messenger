module TcpMsg.Server.Abstract
  ( ConnectionSupplier (ConnectionSupplier, nextConnection, finalize),
    eachConnectionDo,
    eachRequestDo,
    runServer,
  )
where

import Control.Concurrent (forkIO)
import qualified Control.Exception as Exception
import Control.Monad (forever, void)
import Data.Serialize (Serialize)
import Data.Void (Void)
import TcpMsg.Connection (Connection, sendMessage)
import TcpMsg.Data (Header (Header), Message)
import TcpMsg.Parsing (parseMsg)

----------------------------------------------------------------------------------------------------------

data ConnectionSupplier c = ConnectionSupplier
  { nextConnection :: IO (Connection c),
    finalize :: IO ()
  }

eachConnectionDo ::
  ConnectionSupplier c ->
  (Connection c -> IO ()) ->
  IO Void
eachConnectionDo supplier action =
  forever
    ( do
        conn <- nextConnection supplier
        void (forkIO (action conn))
    )

----------------------------------------------------------------------------------------------------------

eachRequestDo ::
  ( Serialize a,
    Serialize b
  ) =>
  Connection c ->
  (Message a -> IO (Message b)) ->
  IO ()
eachRequestDo conn respond =
  forever
    ( do
        (Header messageId _ _, msg) <- parseMsg conn
        inParallel (respond msg >>= conn `sendMessage` messageId)
    )

----------------------------------------------------------------------------------------------------------

runServer ::
  ( Serialize a,
    Serialize b
  ) =>
  ConnectionSupplier c ->
  (Message a -> IO (Message b)) ->
  IO Void
runServer supplier respond =
  Exception.finally
    ( eachConnectionDo
        supplier
        (`eachRequestDo` respond)
    )
    (finalize supplier)

inParallel :: IO () -> IO ()
inParallel = void . forkIO