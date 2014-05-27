{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE JavaScriptFFI            #-}
-- | JavaScript marshalling. This module is pretty unsafe. Be careful.
module Alder.JavaScript
    ( JSValue(..)
    , JSArgs(..)
    , global
    , getProp
    , setProp
    , call
    , apply
    ) where

import           Control.Applicative
import           Control.Monad.Trans
import           Data.Maybe
import           Data.Text          (Text)
import qualified Data.Text          as Text

import           GHCJS.Foreign      hiding (getProp, setProp)
import           GHCJS.Marshal
import           GHCJS.Types

class JSValue a where
    toJSValue   :: a -> IO (JSRef b)
    fromJSValue :: JSRef b -> IO a

instance JSValue () where
    toJSValue   _ = return nullRef
    fromJSValue _ = return ()

instance JSValue (JSRef a) where
    toJSValue   = return . castRef
    fromJSValue = return . castRef

instance JSValue a => JSValue (Maybe a) where
    toJSValue = maybe (return nullRef) toJSValue

    fromJSValue ref
        | isNull ref || isUndefined ref = return Nothing
        | otherwise                     = fromJSValue ref

instance JSValue Bool where
    toJSValue   = return . castRef . toJSBool
    fromJSValue = return . fromJSBool' . castRef

instance JSValue Int where
    toJSValue   = fmap castRef . toJSRef
    fromJSValue = fmap (fromMaybe 0) . fromJSRef . castRef

instance JSValue Text where
    toJSValue       = return . castRef . toJSString
    fromJSValue ref = convert <$> typeOf ref
      where
        convert 4 = fromJSString (castRef ref)
        convert _ = Text.empty

class JSArgs a where
    applyFunction :: JSRef b -> JSString -> a -> IO (JSRef c)

instance (JSValue a, JSValue b) => JSArgs (a, b) where
    applyFunction obj fun (a, b) = do
        arg1 <- toJSValue a
        arg2 <- toJSValue b
        res <- apply2 obj fun arg1 arg2
        fromJSValue res

instance (JSValue a, JSValue b, JSValue c) => JSArgs (a, b, c) where
    applyFunction obj fun (a, b, c) = do
        arg1 <- toJSValue a
        arg2 <- toJSValue b
        arg3 <- toJSValue c
        res <- apply3 obj fun arg1 arg2 arg3
        fromJSValue res

-- | Get a global property value.
global :: (MonadIO m, JSValue a) => Text -> m a
global prop = liftIO $ do
    a <- getGlobal (toJSString prop)
    fromJSValue a

-- | Get a property value.
getProp :: (MonadIO m, JSValue b) => JSRef a -> Text -> m b
getProp obj prop = liftIO $ do
    res <- unsafeGetProp prop obj
    fromJSValue res

-- | Set a property value.
setProp :: (MonadIO m, JSValue b) => JSRef a -> Text -> b -> m ()
setProp obj prop b = liftIO $ do
    val <- toJSValue b
    unsafeSetProp prop val obj

-- | Apply a function to an argument.
call :: (MonadIO m, JSValue b, JSValue c) => JSRef a -> Text -> b -> m c
call obj fun b = liftIO $ do
    arg <- toJSValue b
    res <- apply1 obj (toJSString fun) arg
    fromJSValue res

-- | Apply a function to multiple arguments.
apply :: (MonadIO m, JSArgs b, JSValue c) => JSRef a -> Text -> b -> m c
apply obj fun b = liftIO $ do
    res <- applyFunction obj (toJSString fun) b
    fromJSValue res

foreign import javascript unsafe "$r = window[$1];"
    getGlobal :: JSString -> IO (JSRef a)

foreign import javascript unsafe "$r = $1[$2]($3);"
    apply1 :: JSRef a -> JSString -> JSRef b -> IO (JSRef c)

foreign import javascript unsafe "$r = $1[$2]($3, $4);"
    apply2 :: JSRef a -> JSString -> JSRef b -> JSRef c -> IO (JSRef d)

foreign import javascript unsafe "$r = $1[$2]($3, $4, $5);"
    apply3 :: JSRef a -> JSString
           -> JSRef b -> JSRef c -> JSRef d -> IO (JSRef e)