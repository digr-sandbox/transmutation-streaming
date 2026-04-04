module DataTransformer where

data TransformResult = Success String | Failure String

applyTransformation :: String -> TransformResult
applyTransformation input
    | length input > 10 = Success (reverse input)
    | otherwise = Failure "Input too short"

main :: IO ()
main = putStrLn "Haskell Engine Ready"