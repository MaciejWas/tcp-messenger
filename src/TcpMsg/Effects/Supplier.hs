module TcpMsg.Effects.Supplier where

import Control.Concurrent (forkIO)
import Control.Monad (forever, void)
import Data.Void (Void)
import TcpMsg.Effects.Connection (Connection)

data ConnectionSupplier c = ConnectionSupplier
  { supplyConn :: IO (Connection c),
    finalize :: IO ()
  }

nextConnection :: ConnectionSupplier c -> IO (Connection c)
nextConnection = supplyConn

----------------------------------------------------------------------------------------------------------

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
