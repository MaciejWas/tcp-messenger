{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}

module TcpMsg.Server.Abstract where

import Control.Monad (void)
import qualified Data.ByteString as BS
import Data.ByteString.Lazy (LazyByteString, toStrict)
import Data.Serialize (Serialize, decode)
import Effectful (Eff, IOE, (:>))
import Effectful.Concurrent (Concurrent, forkIO)
import TcpMsg.Effects.Connection (Conn, readBytes, write)
import TcpMsg.Effects.Supplier ( eachConnectionDo, ConnSupplier )
import TcpMsg.Data (Header (Header), headersize)
import TcpMsg.Parsing (parseMsg)


eachRequestDo ::
  forall connState es a b.
  ( Concurrent :> es,
    Serialize a,
    Serialize b
  ) =>
  (a -> Eff (Conn connState ': es) b) ->
  Eff (Conn connState ': es) ()
eachRequestDo respond = do
  (Header messageId _, request) <- parseMsg @connState
  inParallel (respond request >>= write @connState messageId)
  eachRequestDo @connState @es @a @b respond

----------------------------------------------------------------------------------------------------------

runServer ::
  forall connState es a b.
  ( IOE :> es,
    Concurrent :> es,
    ConnSupplier connState :> es,
    Serialize a,
    Serialize b
  ) =>
  (a -> Eff (Conn connState ': es) b) ->
  Eff es ()
runServer respond =
  let respondToRequests = eachRequestDo @connState @es @a @b respond
   in eachConnectionDo (inParallel respondToRequests)

----------------------------------------------------------------------------------------------------------

inParallel :: forall es. (Concurrent :> es) => Eff es () -> Eff es ()
inParallel = void . forkIO