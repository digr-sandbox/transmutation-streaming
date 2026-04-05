{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}

-----------------------------------------------------------------------------

-- |
-- Module      :  Distribution.Simple.Command
-- Copyright   :  Duncan Coutts 2007
-- License     :  BSD3
--
-- Maintainer  :  cabal-devel@haskell.org
-- Portability :  non-portable (ExistentialQuantification)
--
-- This is to do with command line handling. The Cabal command line is
-- organised into a number of named sub-commands (much like darcs). The
-- 'CommandUI' abstraction represents one of these sub-commands, with a name,
-- description, a set of flags. Commands can be associated with actions and
-- run. It handles some common stuff automatically, like the @--help@ and
-- command line completion flags. It is designed to allow other tools make
-- derived commands. This feature is used heavily in @cabal-install@.
module Distribut
