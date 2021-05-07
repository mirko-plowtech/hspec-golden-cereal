
{-|
Module      : Test.Aeson.Internal.GoldenSpecs
Description : Golden tests for Arbitrary
Copyright   : (c) Plow Technologies, 2016
License     : BSD3
Maintainer  : mchaver@gmail.com
Stability   : Beta

Internal module, use at your own risk.
-}

{-# LANGUAGE NamedFieldPuns      #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE RecordWildCards     #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE TypeApplications     #-}

module Test.Aeson.Internal.GoldenSpecs where

import           Control.Exception
import           Control.Monad

import           Data.ByteString.Lazy hiding (putStrLn)
import           Data.Int (Int32)
import           Data.Maybe (isJust)
import           Data.Proxy
import           Data.Typeable
import Data.Coerce

import           Prelude hiding (readFile, writeFile)

import           System.Directory
import           System.Environment (lookupEnv)
import           System.FilePath
import           System.Random

import           Test.Aeson.Internal.Utils
import           Test.Hspec
import           Test.HUnit.Lang (HUnitFailure)
import           Test.QuickCheck

-- | Tests to ensure that JSON encoding has not unintentionally changed. This
-- could be caused by the following:
--
-- - A type's instances of `ToJSON` or 'FromJSON' have changed.
-- - Selectors have been edited, added or deleted.
-- - You have changed version of Aeson the way Aeson serialization has changed
--   works.
--
-- If you run this function and the golden files do not
-- exist, it will create them for each constructor. It they do exist, it will
-- compare with golden file if it exists. Golden file encodes json format of a
-- type. It is recommended that you put the golden files under revision control
-- to help monitor changes.
goldenSpecs :: forall s a . (GoldenSerializer s, Typeable a, Arbitrary a) =>
  Settings -> Proxy a -> Spec
goldenSpecs settings proxy = goldenSpecsWithNote @s settings proxy Nothing

-- | same as 'goldenSpecs' but has the option of passing a note to the
-- 'describe' function.
goldenSpecsWithNote :: forall s a. (GoldenSerializer s, Typeable a, Arbitrary a) =>
  Settings -> Proxy a -> Maybe String -> Spec
goldenSpecsWithNote settings proxy mNote = do
  typeNameInfo    <- runIO $ mkTypeNameInfo settings proxy
  goldenSpecsWithNotePlain @s settings typeNameInfo proxy mNote

-- | same as 'goldenSpecsWithNote' but does not require a Typeable, Eq or Show instance.
goldenSpecsWithNotePlain :: forall s a . (GoldenSerializer s, Arbitrary a) =>
  Settings -> TypeNameInfo a -> Proxy a -> Maybe String -> Spec
goldenSpecsWithNotePlain settings@Settings{..} typeNameInfo@(TypeNameInfo{typeNameTypeName}) proxy mNote = do
  let goldenFile = mkGoldenFile typeNameInfo
      note = maybe "" (" " ++) mNote

  describe ("JSON encoding of " ++ addBrackets  (unTypeName typeNameTypeName) ++ note) $
    it ("produces the same JSON as is found in " ++ goldenFile) $ do
      exists <- doesFileExist goldenFile
      let fixIfFlag err = do
            doFix <- isJust <$> lookupEnv "RECREATE_BROKEN_GOLDEN"
            if doFix
              then createGoldenfile @s settings proxy goldenFile
              else throwIO err
      if exists
        then compareWithGolden @s typeNameInfo proxy goldenFile comparisonFile
          `catches` [ Handler (\(err :: HUnitFailure) -> fixIfFlag err)
                    , Handler (\(err :: DecodeError) -> fixIfFlag err)
                    ]
        else do
          doCreate <- isJust <$> lookupEnv "CREATE_MISSING_GOLDEN"
          if doCreate
            then createGoldenfile @s settings proxy goldenFile
            else expectationFailure $ "Missing golden file: " <> goldenFile

    
-- | The golden files already exist. Serialize values with the same seed from
-- the golden file and compare the with the JSON in the golden file.
compareWithGolden :: forall s a .
  (GoldenSerializer s, Arbitrary a) =>
  TypeNameInfo a ->  Proxy a -> FilePath -> ComparisonFile -> IO ()
compareWithGolden typeNameInfo proxy goldenFile comparisonFile = do  
  fileContent <- readFile goldenFile
  goldenSampleWithoutBody <- unlift <$> readRandomSamplesHeader @s fileContent
  let goldenSeed = seed goldenSampleWithoutBody
  let sampleSize = Prelude.length $ samples $ goldenSampleWithoutBody
  newSamples :: s (RandomSamples a) <- lift <$> mkRandomSamples sampleSize proxy goldenSeed
  whenFails (writeComparisonFile newSamples) $ do
    goldenBytes <- readFile goldenFile
    goldenSamples :: s (RandomSamples a) <- decodeIO goldenBytes
    if encode @s newSamples == encode @s goldenSamples
      then return ()
      else do
        -- fallback to testing roundtrip decoding/encoding of golden file
        putStrLn $
          "\n" ++
          "WARNING: Encoding new random samples do not match " ++ goldenFile ++ ".\n" ++
          "  Testing round-trip decoding/encoding of golden file."
        if encode @s goldenSamples == goldenBytes
          then return ()
          else do
            writeReencodedComparisonFile goldenSamples
            expectationFailure $ "Serialization has changed. Compare golden file with " ++ faultyReencodedFilePath ++ "."
  where
    whenFails :: forall b c . IO c -> IO b -> IO b
    whenFails = flip onException
    filePath =
      case comparisonFile of
        FaultyFile -> mkFaultyFile typeNameInfo
        OverwriteGoldenFile -> goldenFile
    faultyReencodedFilePath = mkFaultyReencodedFile typeNameInfo
    writeComparisonFile newSamples = do
      writeFile filePath (encode @s newSamples)
      putStrLn $
        "\n" ++
        "INFO: Written the current encodings into " ++ filePath ++ "."
    writeReencodedComparisonFile samples = do
      writeFile faultyReencodedFilePath (encode @s samples)
      putStrLn $
        "\n" ++
        "INFO: Written the reencoded goldenFile into " ++ faultyReencodedFilePath ++ "."


-- | The golden files do not exist. Create it.
createGoldenfile :: forall s a . (GoldenSerializer s, Arbitrary a) =>
  Settings -> Proxy a -> FilePath -> IO ()
createGoldenfile Settings{..} proxy goldenFile = do
  createDirectoryIfMissing True (takeDirectory goldenFile)
  rSeed <- randomIO
  rSamples <- lift <$> mkRandomSamples sampleSize proxy rSeed
  writeFile goldenFile (encode @s rSamples)

  putStrLn $
    "\n" ++
    "WARNING: Running for the first time, not testing anything.\n" ++
    "  Created " ++ goldenFile ++ " containing random samples,\n" ++
    "  will compare JSON encodings with this from now on.\n" ++
    "  Please, consider putting " ++ goldenFile ++ " under version control."

-- | Create the file path for the golden file. Optionally use the module name to
-- help avoid name collissions. Different modules can have types of the same
-- name.
mkGoldenFile ::  TypeNameInfo a -> FilePath
mkGoldenFile (TypeNameInfo{typeNameTopDir,typeNameModuleName,typeNameTypeName}) =
  case typeNameModuleName of
    Nothing         -> unTopDir typeNameTopDir </> unTypeName typeNameTypeName <.> "json"
    Just moduleName -> unTopDir typeNameTopDir </> unModuleName moduleName </> unTypeName typeNameTypeName <.> "json"

-- | Create the file path to save results from a failed golden test. Optionally
-- use the module name to help avoid name collisions.  Different modules can
-- have types of the same name.
mkFaultyFile :: TypeNameInfo a -> FilePath
mkFaultyFile (TypeNameInfo {typeNameTypeName,typeNameModuleName, typeNameTopDir})  =
  case unModuleName <$> typeNameModuleName of
    Nothing         -> unTopDir typeNameTopDir </> unTypeName typeNameTypeName <.> "faulty" <.> "json"
    Just moduleName -> unTopDir typeNameTopDir </>  moduleName </> unTypeName typeNameTypeName <.> "faulty" <.> "json"

-- | Create the file path to save results from a failed fallback golden test. Optionally
-- use the module name to help avoid name collisions.  Different modules can
-- have types of the same name.
mkFaultyReencodedFile :: TypeNameInfo a -> FilePath
mkFaultyReencodedFile (TypeNameInfo {typeNameTypeName,typeNameModuleName, typeNameTopDir})  =
  case unModuleName <$> typeNameModuleName of
    Nothing         -> unTopDir typeNameTopDir </> unTypeName typeNameTypeName <.> "faulty" <.> "reencoded" <.> "json"
    Just moduleName -> unTopDir typeNameTopDir </>  moduleName </> unTypeName typeNameTypeName <.> "faulty" <.> "reencoded"  <.> "json"

-- | Create a number of arbitrary instances of a type
-- a sample size and a random seed.
mkRandomSamples :: forall a . (Arbitrary a) =>
  Int -> Proxy a -> Int32 -> IO (RandomSamples a)
mkRandomSamples sampleSize Proxy rSeed = (RandomSamples rSeed) <$> generate gen
  where
    correctedSampleSize = if sampleSize <= 0 then 1 else sampleSize
    gen :: Gen [a]
    gen = setSeed (fromIntegral rSeed) $ replicateM correctedSampleSize (arbitrary :: Gen a)
