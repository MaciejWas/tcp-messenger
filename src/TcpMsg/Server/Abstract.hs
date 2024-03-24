{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}

module TcpMsg.Server.Abstract where

import Control.Monad (void)
import Data.Serialize (Serialize)
import Effectful (Eff, IOE, (:>))
import Effectful.Concurrent (Concurrent, forkIO)
import TcpMsg.Effects.Connection (Conn, readBytes, sendMessage)
import TcpMsg.Effects.Supplier ( eachConnectionDo, ConnSupplier )
import TcpMsg.Data (Header (Header), headersize)
import TcpMsg.Parsing (parseMsg)
import Effectful.Dispatch.Static (unsafeEff_)

eachRequestDo ::
  forall connState es a b.
  ( Concurrent :> es,
    Serialize a,
    Serialize b
  ) =>
  (a -> IO (Message b)) ->
  Eff (Conn connState ': es) ()
eachRequestDo respond = do
  (Header messageId _ _, ) <- parseMsg @connState
  inParallel (unsafeEff_ (respond request) >>= sendMessage @connState messageId)
  eachRequestDo @connState @es @a @b respond

----------------------------------------------------------------------------------------------------------

runServer ::
  forall a b connState es.
  ( IOE :> es,
    Concurrent :> es,
    ConnSupplier connState :> es,
    Serialize a,
    Serialize b
  ) =>
  (a -> IO b) ->
  Eff es ()
runServer respond =
  let respondToRequests = eachRequestDo @connState @es @a @b respond
   in eachConnectionDo (inParallel respondToRequests)

----------------------------------------------------------------------------------------------------------

inParallel :: forall es. (Concurrent :> es) => Eff es () -> Eff es ()
inParallel = void . forkIO