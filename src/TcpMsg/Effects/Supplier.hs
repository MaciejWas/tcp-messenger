{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}


module TcpMsg.Effects.Supplier where


import Control.Concurrent (forkIO)
import Control.Monad (forever, void)
import Data.Void (Void)
import TcpMsg.Effects.Connection (Connection)

newtype ConnectionSupplier c = ConnectionSupplier {supplyConn :: IO (Connection c)}

nextConnection :: ConnectionSupplier c -> IO (Connection c)
nextConnection = supplyConn

----------------------------------------------------------------------------------------------------------

eachConnectionDo ::
  forall c.
  ConnectionSupplier c ->
  (Connection c -> IO ()) ->
  IO Void
eachConnectionDo supplier action =
  forever
    ( do
        conn <- nextConnection supplier
        void (forkIO (action conn))
    )
