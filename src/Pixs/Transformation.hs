{-# LANGUAGE FlexibleInstances  #-}
{-# LANGUAGE UnicodeSyntax      #-}

module Pixs.Transformation ( blur
                           , flipVertical
                           , flipHorizontal
                           , flip
                           , changeRed
                           , changeGreen
                           , changeBlue
                           , changeBrightness
                           , negateImage
                           , saturation
                           , getPixel
                           , average
                           , (⊕)
                           , safeAdd
                           , (⊗)
                           , safeMultiply
                           , pixelDiv
                           , scale) where


import Prelude hiding (flip)
import Data.Word
import Data.Maybe (catMaybes)
import Codec.Picture( PixelRGBA8(..)
                    , Image(..)
                    , Pixel
                    , pixelMap
                    , imageHeight
                    , imageWidth
                    , pixelAt
                    , generateImage)

-- | Used for reducing repetition when declaring Num instance.
--   Our strategy for overflow/underflow checking is the same for all of the
--   operations so we define this function that takes in an operation and two
--   pixels and applies the operation to the components. Pixel addition for
--   example is implemented by simply passing (+) to `applyOp`.
applyOp ∷ (Int → Int → Int) → PixelRGBA8 → PixelRGBA8 → PixelRGBA8
applyOp op (PixelRGBA8 r₁ g₁ b₁ a₁) (PixelRGBA8 r₂ g₂ b₂ a₂)
  = PixelRGBA8 r g b (max a₁ a₂)
  where r' = (fromIntegral r₁ `op` fromIntegral r₂)
        g' = (fromIntegral g₁ `op` fromIntegral g₂)
        b' = (fromIntegral b₁ `op` fromIntegral b₂)
        r  = fromIntegral . max 0 . min 255 $ r'   ∷ Word8
        g  = fromIntegral . max 0 . min 255 $ g'   ∷ Word8
        b  = fromIntegral . max 0 . min 255 $ b'   ∷ Word8

--   TODO: PixelRGBA8 should not really have an instance of
--   Num since it doesn't behave like a number. For
--   now we declare a num instance for the convenience of
--   being able to use (+), (-) etc... It would be the best
--   it were a VectorSpace if a VectorSpace typeclass exists
--   somewhere. Or maybe, that's too much; I don't know.
instance Num PixelRGBA8 where

  negate (PixelRGBA8 r g b _) = PixelRGBA8 r' g' b' 255
    where r' = 255 - r
          g' = 255 - g
          b' = 255 - b

  (+) = applyOp (+)

  (-) = applyOp (-)

  (*) = applyOp (*)

  abs p = p

  signum p = p

  fromInteger _ = undefined

pixelDiv ∷ PixelRGBA8 → PixelRGBA8 → PixelRGBA8
pixelDiv = applyOp div

-- | Flow-checked addition operation which we denote with ⊕.
-- Also has an ASCII alias `safeAdd`.
(⊕) ∷ Word8 → Int → Word8
(⊕) x y = let x' = (fromIntegral x) ∷ Int
              y' = (fromIntegral y) ∷ Int
          in fromIntegral . max 0 . min 255 $ x' + y'

safeAdd ∷ Word8 → Int → Word8
safeAdd = (⊕)

-- | Flow-checked multiplication operation.
-- Also has an ASCII alias `safeMultiply`.
(⊗) ∷ Word8 → Int → Word8
(⊗) x y = let x' = (fromIntegral x) ∷ Int
              y' = (fromIntegral y) ∷ Int
          in fromIntegral . max 0 . min 255 $ x' * y'

safeMultiply ∷ Word8 → Int → Word8
safeMultiply = (⊗)

-- | Scalar multiplication.
scale ∷ Double → PixelRGBA8 → PixelRGBA8
scale n (PixelRGBA8 r g b a) = let r' = (fromIntegral r) ∷ Double
                                   g' = (fromIntegral g) ∷ Double
                                   b' = (fromIntegral b) ∷ Double
                                   [r'', g'', b''] = map (* n) [r', g', b']
                                   rFin = round . max 0 . min 255 $ r''
                                   gFin = round . max 0 . min 255 $ g''
                                   bFin = round . max 0 . min 255 $ b''
                               in PixelRGBA8 rFin gFin bFin a

changeBrightness ∷ Int → Image PixelRGBA8 → Image PixelRGBA8
changeBrightness amount = pixelMap changeBrightness'
  where changeBrightness' (PixelRGBA8 r g b a) = PixelRGBA8 r' g' b' a
          where r' = r ⊕ amount
                g' = g ⊕ amount
                b' = b ⊕ amount

changeRed ∷ Int → Image PixelRGBA8 → Image PixelRGBA8
changeRed amount = pixelMap changeRed'
  where changeRed' (PixelRGBA8 r g b a) = PixelRGBA8 (r ⊕ amount) g b a

changeGreen ∷ Int → Image PixelRGBA8 → Image PixelRGBA8
changeGreen amount = pixelMap changeGreen'
  where changeGreen' (PixelRGBA8 r g b a) = PixelRGBA8 r g' b a
                                            where g' = g ⊕ amount

changeBlue ∷ Int → Image PixelRGBA8 → Image PixelRGBA8
changeBlue amount = pixelMap changeBlue'
  where changeBlue' (PixelRGBA8 r g b a) = PixelRGBA8 r g b' a
                                            where b' = b ⊕ amount

saturation ∷ Int → Image PixelRGBA8 → Image PixelRGBA8
saturation amount = changeRed amount . changeGreen amount . changeBlue amount

flipVertical ∷ Pixel a ⇒ Image a → Image a
flipVertical img =  generateImage complement (imageWidth img) (imageHeight img)
  where complement x y = pixelAt img x (imageHeight img - y - 1)

flipHorizontal ∷ Pixel a ⇒ Image a → Image a
flipHorizontal img = generateImage complement (imageWidth img) (imageHeight img)
  where complement x y = pixelAt img (imageWidth img - x - 1) y

flip ∷ Pixel a ⇒ Image a → Image a
flip = flipVertical . flipHorizontal

-- | Take a list of pixels. Return the pixel that is the average color of
-- those pixels.
average ∷ [PixelRGBA8] → PixelRGBA8
average pixs = let avg xs   = sum xs `div` length xs
                   redAvg ∷ Word8
                   redAvg   = fromIntegral $ avg [fromIntegral r ∷ Int
                                                 | (PixelRGBA8 r _ _ _) ← pixs ]
                   greenAvg ∷ Word8
                   greenAvg = fromIntegral $ avg [fromIntegral g ∷ Int
                                                 | (PixelRGBA8 _ g _ _) ← pixs]
                   blueAvg ∷ Word8
                   blueAvg = fromIntegral $ avg [fromIntegral b ∷ Int
                                                | (PixelRGBA8 _ _ b _) ← pixs]
               in PixelRGBA8 redAvg greenAvg blueAvg 255

-- | Try to access pixel at x y. Yield nothing if the given coordinates
-- are out of bounds.
getPixel ∷ Image PixelRGBA8 → Int → Int → Maybe PixelRGBA8
getPixel img x y = let xInBounds = x < imageWidth  img && x >= 0
                       yInBounds = y < imageHeight img && y >= 0
                   in if xInBounds && yInBounds
                      then Just $ pixelAt img x y
                      else Nothing

-- TODO: This is a naive implementation---optimize this.
-- | For every pixel p in an image, assign the average of p's
-- neighborhood at distance n, to p.
blur ∷  Image PixelRGBA8 → Int → Image PixelRGBA8
blur img n = let neighbors x y = catMaybes [getPixel img (x - i) (y - j)
                                           | i ← [(-n)..n]
                                           , j ← [(-n)..n]]
                 w = imageWidth  img
                 h = imageHeight img
             in generateImage (\x y → average (neighbors x y)) w h

-- | Negate the color of a given image.
negateImage ∷ Image PixelRGBA8 → Image PixelRGBA8
negateImage img = pixelMap negate img
