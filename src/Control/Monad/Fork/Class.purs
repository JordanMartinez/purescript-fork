{-
Copyright 2017 SlamData, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-}

module Control.Monad.Fork.Class where

import Prelude hiding (join)

import Control.Monad.Aff as Aff
import Control.Monad.Error.Class (class MonadThrow, class MonadError)
import Control.Monad.Reader.Trans (ReaderT(..), runReaderT)
import Control.Monad.Trans.Class (lift)

-- | Represents Monads which can be forked asynchronously.
-- |
-- | Laws:
-- |
-- | ```purescript
-- | suspend >=> join = id
-- | join t *> join t = join t
-- | ```
class (Monad m, Functor f) ⇐ MonadFork f m | m → f where
  suspend ∷ ∀ a. m a → m (f a)
  fork ∷ ∀ a. m a → m (f a)
  join ∷ ∀ a. f a → m a

instance monadForkAff ∷ MonadFork (Aff.Fiber eff) (Aff.Aff eff) where
  suspend = Aff.suspendAff
  fork = Aff.forkAff
  join = Aff.joinFiber

instance monadForkReaderT ∷ MonadFork f m ⇒ MonadFork f (ReaderT r m) where
  suspend (ReaderT ma) = ReaderT (suspend <<< ma)
  fork (ReaderT ma) = ReaderT (fork <<< ma)
  join = lift <<< join

-- | Represents Monads which can be killed after being forked.
-- |
-- | Laws:
-- |
-- | ```purescript
-- | (do t <- suspend (throwError e1)
-- |     kill e2 t
-- |     join t)
-- |   = throwError e2
-- |
-- | (do t <- fork (pure a)
-- |     kill e2 t
-- |     join t)
-- |   = pure a
-- | ```
class (MonadFork f m, MonadThrow e m) ⇐  MonadKill e f m | m → e f where
  kill ∷ ∀ a. e → f a → m Unit

instance monadKillAff ∷ MonadKill Aff.Error (Aff.Fiber eff) (Aff.Aff eff) where
  kill = Aff.killFiber

instance monadKillReaderT ∷ MonadKill e f m ⇒ MonadKill e f (ReaderT r m) where
  kill e = lift <<< kill e

data BracketCondition e a
  = Completed a
  | Failed e
  | Killed e

-- | Represents Monads which support cleanup in the presence of async
-- | exceptions.
class (MonadKill e f m, MonadError e m) ⇐ MonadBracket e f m | m → e f where
  bracket ∷ ∀ r a. m r → (BracketCondition e a → r → m Unit) → (r → m a) → m a
  never ∷ ∀ a. m a

instance monadBracketAff ∷ MonadBracket Aff.Error (Aff.Fiber eff) (Aff.Aff eff) where
  bracket acquire release run =
    Aff.generalBracket acquire
      { completed: release <<< Completed
      , failed: release <<< Failed
      , killed: release <<< Killed
      }
      run
  never = Aff.never

instance monadBracketReaderT ∷ MonadBracket e f m ⇒ MonadBracket e f (ReaderT r m) where
  bracket (ReaderT acquire) release run = ReaderT \r →
    bracket (acquire r)
      (\c a → runReaderT (release c a) r)
      (\a → runReaderT (run a) r)
  never = lift never
