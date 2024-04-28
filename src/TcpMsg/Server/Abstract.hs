{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
module TcpMsg.Server.Abstract
  ( ConnectionSupplier (ConnectionSupplier, nextConnection, finalize),
    eachConnectionDo,
    runServer,
  )
where

import Control.Concurrent (forkIO)
import qualified Control.Exception as Exception
import Control.Monad (forever, void)
import Data.Serialize (Serialize)
import Data.Void (Void)
import TcpMsg.Connection (Connection, reply)
import TcpMsg.Data (Message)

----------------------------------------------------------------------------------------------------------

data ConnectionSupplier c a b = ConnectionSupplier
  { nextConnection :: IO (Connection c a b),
    finalize :: IO ()
  }

eachConnectionDo ::
  ConnectionSupplier c a b->
  (Connection c a b -> IO ()) ->
  IO Void
eachConnectionDo supplier action =
  forever
    ( do
        conn <- nextConnection supplier
        void (forkIO (action conn))
    )

----------------------------------------------------------------------------------------------------------

runServer ::
  forall a b c.
  ( Serialize a, Serialize b ) =>
  ConnectionSupplier c a b ->
  (Message a -> IO (Message b)) ->
  IO Void
runServer supplier respond =
  Exception.finally
    ( eachConnectionDo
        supplier
        (\conn -> reply @a @b conn respond)
    )
    (finalize supplier)
