module TcpMsg.Parsing where

import qualified Data.ByteString as BS
import Data.ByteString.Lazy (LazyByteString, toStrict)
import qualified Data.ByteString.Lazy as LBS
import Data.Serialize (Serialize, decode)
import TcpMsg.Data (Header (Header), Message (Message), headersize, FullMessage (FullMessage))

type BytesSupplier = Int -> IO BS.ByteString

parseMsg ::
  (Serialize a) => BytesSupplier -> IO (FullMessage a)
parseMsg conn = do
  header <- parseHeader conn
  payload <- parsePayload conn header
  trunk <- parseTrunk conn header
  return (FullMessage header (Message payload trunk) mempty)

parseHeader :: BytesSupplier -> IO Header
parseHeader conn = parse conn headersize

parsePayload :: (Serialize m) => BytesSupplier -> Header -> IO m
parsePayload c (Header _ msgSize _) = parse c msgSize

parseTrunk :: BytesSupplier -> Header -> IO (Maybe LBS.LazyByteString)
parseTrunk conn (Header _ _ trunkSize) = case trunkSize of
  0 -> return Nothing
  _ -> do
    buf <- buffer conn mempty (fromIntegral trunkSize)
    return (if BS.null buf then Nothing else Just (LBS.fromStrict buf))

parse :: (Serialize a) => BytesSupplier -> Int -> IO a
parse conn n = do
  buf <- buffer conn (mempty :: LazyByteString) n
  case decode buf of
    Right val -> return val
    Left e -> error e

buffer :: BytesSupplier -> LazyByteString -> Int -> IO BS.ByteString
buffer readBytes currBuffer remainingBytes = do
  newBytes <- readBytes remainingBytes
  let bytesInLastMessage = BS.length newBytes
  if bytesInLastMessage == remainingBytes
    then return (toStrict currBuffer <> newBytes)
    else
      let updatedBuffer = currBuffer <> BS.fromStrict newBytes
          updatedRemaining = remainingBytes - bytesInLastMessage
       in buffer readBytes updatedBuffer updatedRemaining
