{-# LANGUAGE NamedFieldPuns #-}
module TcpMsg.Effects.Client where

import Control.Concurrent (ThreadId)
import Control.Concurrent.Async (Async, async)
import Control.Concurrent.STM (atomically)
import qualified Control.Concurrent.STM as STM
import Data.Serialize (Serialize)
import qualified Data.Text as T
import Data.UnixTime (getUnixTime)
import qualified Network.Socket as Net
import qualified StmContainers.Map as M
import TcpMsg.Data (Message, UnixMsgTime, fromUnix)
import TcpMsg.Effects.Connection (Connection, sendMessage)
