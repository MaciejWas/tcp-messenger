{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

module TcpMsg.Effects.Logger where

import Control.Concurrent (ThreadId)
-- import qualified Data.HashTable.IO as H (BasicHashTable, insert, lookup, new)

import qualified Control.Concurrent.STM as STM
import Control.Monad (forever)
import Data.Serialize (Serialize)
import qualified Data.Text as T
import Data.UnixTime (getUnixTime)
import Effectful
  ( Dispatch (Static),
    DispatchOf,
    Eff,
    Effect,
    IOE,
    (:>),
  )
import Effectful.Concurrent (Concurrent, forkIO)
import Effectful.Concurrent.Async (Async, async)
import Effectful.Concurrent.STM (atomically)
import Effectful.Dispatch.Static
  ( SideEffects (WithSideEffects),
    StaticRep,
    evalStaticRep,
    getStaticRep,
    unsafeEff_,
  )
import qualified StmContainers.Map as M
import TcpMsg.Data (Header (Header), UnixMsgTime, fromUnix, Message)
import TcpMsg.Effects.Connection (Conn, sendMessage)
import TcpMsg.Parsing (parseMsg)
import qualified Data.ByteString.Lazy as LBS
import qualified Data.ByteString as BS

----------------------------------------------------------------------------------------------------------

data LoggerActions = LoggerActions
  { info :: BS.ByteString -> IO (),
    debug :: BS.ByteString -> IO ()
  }

----------------------------------------------------------------------------------------------------------

data Logger :: Effect

type instance DispatchOf Logger = Static WithSideEffects

newtype instance StaticRep Logger = Logger LoggerActions

----------------------------------------------------------------------------------------------------------

logInfo :: forall es. (Logger :> es) => BS.ByteString -> Eff es ()
logInfo msg = do
  (Logger (LoggerActions{info})) <- (getStaticRep :: Eff es (StaticRep Logger))
  unsafeEff_ (info msg)

logDebug :: forall es. (Logger :> es) => BS.ByteString -> Eff es ()
logDebug msg = do
  (Logger (LoggerActions{debug})) <- (getStaticRep :: Eff es (StaticRep Logger))
  unsafeEff_ (debug msg)
  