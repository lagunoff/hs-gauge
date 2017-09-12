{-# LANGUAGE CPP, OverloadedStrings #-}

-- |
-- Module      : Gauge.IO
-- Copyright   : (c) 2009-2014 Bryan O'Sullivan
--
-- License     : BSD-style
-- Maintainer  : bos@serpentine.com
-- Stability   : experimental
-- Portability : GHC
--
-- Input and output actions.

module Gauge.IO
    (
      header
    , headerRoot
    , critVersion
    , hGetRecords
    , hPutRecords
    , readRecords
    , writeRecords
    , ReportFileContents
    ) where

import Data.Binary (Binary(..), encode)
#if MIN_VERSION_binary(0, 6, 3)
import Data.Binary.Get (runGetOrFail)
#else
import Data.Binary.Get (runGetState)
#endif
import Data.Binary.Put (putByteString, putWord16be, runPut)
import qualified Data.ByteString.Char8 as B
import Gauge.Types (Report(..))
import Data.List (intercalate)
import Data.Version (Version(..))
import Paths_gauge (version)
import System.IO (Handle, IOMode(..), withFile, hPutStrLn, stderr)
import qualified Data.ByteString.Lazy as L

-- | The header identifies a gauge data file. This contains
-- version information; there is no expectation of cross-version
-- compatibility.
header :: L.ByteString
header = runPut $ do
  putByteString (B.pack headerRoot)
  mapM_ (putWord16be . fromIntegral) (versionBranch version)

-- | The magic string we expect to start off the header.
headerRoot :: String
headerRoot = "criterio"

-- | The current version of gauge, encoded into a string that is
-- used in files.
critVersion :: String
critVersion = intercalate "." $ map show $ versionBranch version

-- | Read all records from the given 'Handle'.
hGetRecords :: Binary a => Handle -> IO (Either String [a])
hGetRecords handle = do
  bs <- L.hGet handle (fromIntegral (L.length header))
  if bs == header
    then Right `fmap` readAll handle
    else return $ Left $ "unexpected header, expected gauge version: "++show (versionBranch version)

-- | Write records to the given 'Handle'.
hPutRecords :: Binary a => Handle -> [a] -> IO ()
hPutRecords handle rs = do
  L.hPut handle header
  mapM_ (L.hPut handle . encode) rs

-- | Read all records from the given file.
readRecords :: Binary a => FilePath -> IO (Either String [a])
readRecords path = withFile path ReadMode hGetRecords

-- | Write records to the given file.
writeRecords :: Binary a => FilePath -> [a] -> IO ()
writeRecords path rs = withFile path WriteMode (flip hPutRecords rs)

#if MIN_VERSION_binary(0, 6, 3)
readAll :: Binary a => Handle -> IO [a]
readAll handle = do
  let go bs
         | L.null bs = return []
         | otherwise = case runGetOrFail get bs of
                         Left (_, _, err) -> fail err
                         Right (bs', _, a) -> (a:) `fmap` go bs'
  go =<< L.hGetContents handle
#else
readAll :: Binary a => Handle -> IO [a]
readAll handle = do
  let go i bs
         | L.null bs = return []
         | otherwise =
            let (a, bs', i') = runGetState get bs i
             in (a:) `fmap` go i' bs'
  go 0 =<< L.hGetContents handle
#endif

-- | On disk we store (name,version,reports), where
--   'version' is the version of Criterion used to generate the file.
type ReportFileContents = (String,String,[Report])
