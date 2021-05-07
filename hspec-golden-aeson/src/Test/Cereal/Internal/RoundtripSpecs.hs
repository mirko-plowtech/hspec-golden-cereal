{-|
Module      : Test.Cereal.Internal.RoundtripSpecs
Description : Roundtrip tests for Arbitrary
Copyright   : (c) Plow Technologies, 2016
License     : BSD3
Maintainer  : mchaver@gmail.com
Stability   : Beta

Internal module, use at your own risk.
-}

{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications     #-}

module Test.Cereal.Internal.RoundtripSpecs where

import           Data.Aeson as Aeson
import           Data.Typeable

import           Test.Cereal.Internal.Utils
import           Test.Hspec
import           Test.QuickCheck
import           Test.Hspec.QuickCheck
-- | A roundtrip test to check whether values of the given type
-- can be successfully converted to JSON and back to a Haskell value.
--
-- 'roundtripSpecs' will
--
-- - create random values (using 'Arbitrary'),
-- - convert them into JSON (using 'ToJSON'),
-- - read them back into Haskell (using 'FromJSON') and
-- - make sure that the result is the same as the value it started with
--   (using 'Eq').

roundtripSpecs :: forall s a .
  (Typeable a, Show (s a), Arbitrary (s a), GoldenSerializer s, Ctx s a) =>
  Proxy (s a) -> Spec
roundtripSpecs proxy = genericAesonRoundtripWithNote proxy Nothing

-- | Same as 'roundtripSpecs', but optionally add notes to the 'describe'
-- function.
genericAesonRoundtripWithNote :: forall s a .
  (Typeable a, Show (s a), Arbitrary (s a), GoldenSerializer s, Ctx s a) =>
  Proxy (s a) -> Maybe String -> Spec
genericAesonRoundtripWithNote proxy mNote = do
  let typeIdentifier = show (typeRep (Proxy :: Proxy a))
  result <- genericAesonRoundtripWithNotePlain proxy mNote typeIdentifier
  return result

-- | Same as 'genericAesonRoundtripWithNote', but no need for Typeable, Eq, or Show
genericAesonRoundtripWithNotePlain :: forall s a .
  (Show (s a), Arbitrary (s a), GoldenSerializer s, Ctx s a) =>
  Proxy (s a) -> Maybe String -> String -> Spec
genericAesonRoundtripWithNotePlain _ mNote typeIdentifier = do
  let note = maybe "" (" " ++) mNote
  
  describe ("JSON encoding of " ++ addBrackets (typeIdentifier) ++ note) $
    prop "allows to encode values with aeson and read them back"  
          (checkEncodingEquality @s @a )