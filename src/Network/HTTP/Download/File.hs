module Network.HTTP.Download.File
  ( -- * Introduction
    --
    -- $Introduction
    downloadFile
  , Overwrite(..)
  , ProxyAuth(..)
  )

where
import System.Process
import System.Exit
import Network.URI
import Control.Exception
import System.Info(os,arch)
import System.Directory
import System.FilePath
import Paths_downloader(getDataDir, version)
import Data.Version(showVersion)
import GHC.Stack
import Safe

-- | A 'Bool' wrapper that is passed to 'downloadFile' and
-- which if set to @(Overwrite True)@ will allow 'downloadFile' to
-- overwrite an existing file.
newtype Overwrite = Overwrite { _overwrite :: Bool }

-- | Used for proxy authentication:
-- @Basic ("user", "pass")@ indicates that the proxy needs
-- <https://en.wikipedia.org/wiki/Basic_access_authentication basic authentication>
-- and where the username is "user" and the password is "pass".
-- whereas with @Digest ("user", "pass")@
-- <https://en.wikipedia.org/wiki/Digest_access_authentication digest authentication>
-- is used instead.
--
-- In a nutshell with Basic Auth your password is sent over the network in clear
-- text so anyone monitoring traffic can see it. With digest auth each request
-- generates two calls, the first gets the proxy's unique hash key and the second
-- sends the actual request with the password hashed using the unique key so
-- anyone monitoring web traffic only sees it encrypted.
data ProxyAuth = Basic (String, String) | Digest (String, String) deriving Show

{-|
  Downloads a file from the given URL via a GET request to the specified
  location on the filesystem and returns the _absolute_ and canonicalized path
  to that location.

  On Windows the download itself delegates to a
  <https://en.wikipedia.org/wiki/PowerShell PowerShell> script and wraps
  <https://curl.haxx.se/ curl> on all other platforms. The user agent for the
  request is "downloader\/\<downloader-version\>(\<os\>;\<arch\>)", eg. when version
  0.1.0.0 of this package is run on 64 bit Linux the user agent is
  "downloader\/0.1.0.0(linux;x86_64)"

  Only HTTP and HTTPS transport protocols are supported. If a URL does not
  specify a protocol it is prefixed with "https:", eg. given URL string
  "www.google.com" this function will make a request to "https://www.google.com".

  The output directory may be relative but must exist.

  The output filename must be just a valid, unqualified filename, eg. "file.txt" is
  fine but "..\/..\/a\/b\/c\/file.txt" is rejected.

  This function will throw an IO exception in the following cases:

  - A badly formed URL
  - A URL that specifies a protocol that is not http or https, eg. "ftp" will be rejected
  - A badly formed proxy URL.
  - A non existent directory or one that isn't writeable
  - An <https://hackage.haskell.org/package/filepath/docs/System-FilePath-Posix.html#v:isValid invalid> output filename
  - A filename that includes parent directories eg, "a\/b\/c\/file.txt"
  - An HTTP status that is not 200 is returned by the request
  - Any other error returned by 'curl' or PowerShell.
-}

downloadFile :: HasCallStack
  => String    -- ^ URL from which to download a file (or web page)
  -> Maybe (String, Maybe ProxyAuth) -- ^ Proxy authentication, eg. @Just ("http://192.168.0.10:3128", Just (Digest ("user", "pass")))@
  -> FilePath  -- ^ Directory in which to save the file (it must exist)
  -> FilePath  -- ^ File name into which to save the downloaded data
  -> Overwrite -- ^ Optionally overwrite the file if it already exists
  -> IO FilePath
downloadFile urlString proxyInfo directory outputFilename overwrite = do
  u <- getUrl
  o <- getOutputPath
  proxyM <-
    case proxyInfo of
      Just pi -> Just <$> getProxyUrl pi
      Nothing -> pure Nothing
  -- drop the '?' from the query params.
  -- Both the curl command and Powershell script
  -- add it back in before making the web request.
  let (urlOnly, queryParams) = (u { uriQuery = ""}, drop 1 (uriQuery u))
  if (os == "mingw32")
    then do
    res <- lines <$> runPowershellDownload urlOnly proxyM queryParams o
    case res of
      (['2','0','0']:_) -> pure o
      _ -> throwIO (userError (unlines res))
    else do
    res <- runCurlDownload urlOnly proxyM queryParams o
    case res of
      Left err -> throwIO (userError err)
      Right Nothing -> throwIO (userError $ "No output from download process, expected an HTTP return code")
      Right (Just httpCode) ->
        if (httpCode == 200)
        then pure o
        else throwIO (userError $ "HTTP Error code: " ++ show httpCode)
  where
    userAgent :: String
    userAgent = "downloader/" ++ showVersion version ++ "(" ++ os ++ ";" ++ arch ++ ")"
    inDataDir :: FilePath -> IO FilePath
    inDataDir f = (\dd -> dd </> "scripts" </> f) <$> getDataDir
    shScript :: IO String
    shScript = inDataDir "download.sh"
    powershellScript :: IO String
    powershellScript = inDataDir "download.ps1"
    getProxyUrl :: (String, Maybe ProxyAuth) -> IO (URI, Maybe ProxyAuth)
    getProxyUrl (urlString, auth) =
      case parseURI urlString of
        Nothing -> throwIO (userError $ "Failed to parse the proxy URL: " ++ urlString)
        Just url -> pure (url, auth)
    getUrl :: IO URI
    getUrl =
      -- break out query params because spaces don't parse.
      -- They are url encoded in the Powershell and curl calls.
      let (urlOnly, queryParams) = break ((==) '?') urlString
      in
      case parseURI urlOnly of
        Nothing ->
          case (parseURI $ "https://" ++ urlOnly) of
            Nothing -> throwIO (userError $ "Failed to parse URL: " ++ urlString)
            Just url -> pure $ url { uriQuery = queryParams }
        Just url ->
          if (not (uriScheme url `elem` ["http:", "https:"]))
          then throwIO (userError $ "Only http or https are allowed in URL but given: " ++ uriScheme url)
          else pure $ url { uriQuery = queryParams }
    getOutputPath :: IO FilePath
    getOutputPath = do
      f <- if (null outputFilename)
           then throwIO (userError $ "Output filename is empty.")
           else if (not (isValid outputFilename))
                then throwIO (userError $ "Output filename is not valid: " ++ outputFilename ++ "\n. The 'filepath' package has a 'makeValid' function which may be useful.")
                else pure outputFilename
      if (takeDirectory f /= ".")
        then throwIO (userError $ "Output filename must be just a file name without any directories, instead got: " ++ outputFilename)
        else do
        d <- do
          absoluteDirectory <- canonicalizePath directory
          exists <- doesDirectoryExist absoluteDirectory
          if (not exists)
            then throwIO (userError $ "Output directory does not exist: " ++ directory)
            else do
            perms <- getPermissions absoluteDirectory
            if (not (writable perms))
              then throwIO (userError $ "Output directory does not have write permissions: " ++ directory)
              else pure absoluteDirectory
        let outputPath = d </> f
        opExists <- doesFileExist outputPath
        if (opExists && not (_overwrite overwrite))
          then throwIO (userError $ "The output file already exists: " ++ outputPath)
          else pure outputPath
    runCurlDownload ::  URI -> Maybe (URI, Maybe ProxyAuth) -> String -> FilePath -> IO (Either String (Maybe Int))
    runCurlDownload url proxyInfo queryParams outputPath = do
      downloadSh <- shScript
      let args =
            [downloadSh, show url, show queryParams, outputPath, show userAgent] ++
            (case proxyInfo of
               Nothing -> []
               Just (proxyUrl, Nothing) -> [show proxyUrl]
               Just (proxyUrl, Just (Basic (user,pass))) -> [show proxyUrl, user ++ ":" ++ pass, "basic"]
               Just (proxyUrl, Just (Digest (user,pass))) -> [show proxyUrl, user ++ ":" ++ pass, "digest"])
      (exitCode,stdout,stderr) <- readProcessWithExitCode "sh" args ""
      case exitCode of
        ExitSuccess -> do
          if (not (null stdout))
          then case readMay stdout of
            Nothing -> throwIO (userError $ "Expecting a number, got: " ++ stdout)
            Just res -> pure (Right (Just res))
          else pure (Right Nothing)
        ExitFailure errCode -> do
          pure $ Left $ show errCode ++
            (if (not (null stderr))
             then ":" ++ stderr
             else "")
    runPowershellDownload :: URI -> Maybe (URI, Maybe ProxyAuth) -> String -> FilePath -> IO String
    runPowershellDownload url proxyInfo queryParams outputPath = do
      downloadWin <- powershellScript
      let args =
            [ "-ExecutionPolicy", "bypass"
            , "-NonInteractive"
            , "-NoProfile"
            , "-File", downloadWin
            , "-url" , show url
            , "-outputPath" , outputPath
            , "-userAgent", userAgent
            ] ++
            (if (not (null queryParams))
            then [ "-queryParams" , queryParams ]
            else []) ++
            (case proxyInfo of
               Nothing -> []
               Just (proxyUrl, Nothing) -> ["-proxy", show proxyUrl]
               Just (proxyUrl, Just (Basic (user,pass))) -> [ "-proxy", show proxyUrl, "-user", user, "-pass", pass, "-auth", "basic" ]
               Just (proxyUrl, Just (Digest (user,pass))) -> [ "-proxy", show proxyUrl, "-user", user, "-pass", pass, "-auth", "digest" ])
      (_,stdout,_) <- readProcessWithExitCode "powershell.exe" args ""
      pure stdout

-- $Introduction
-- This micro library consists of a single cross platform function
-- 'downloadFile' which downloads a file off the Web and to your filesystem. It
-- is very light on dependencies and configurability and ultimately just a
-- wrapper around a <https://en.wikipedia.org/wiki/PowerShell PowerShell> script
-- on Windows and <https://curl.haxx.se/ curl> on Linux and macOS. Both
-- Powershell and 'curl' should be available out-of-the-box.
--
-- To set expectations 'downloadFile' is lo-fi and deliberately under-engineered.
-- The download request blocks until it is done, all errors are thrown as
-- unrecoverable IO exceptions and any errors that occur at the 'curl' or
-- 'PowerShell' level are bubbled up to the user as is. If you don't care about
-- low dependencies and a small API or need recoverable errors and socket pooling,
-- <http://hackage.haskell.org/package/http-client http-client> is a
-- much nicer package with many more options.
--
-- I wrote this because I needed an easy, low-dependency way to download files off
-- the Internet across platforms at /build/ /time/. I have a
-- <https://github.com/deech/cabal-downloader-demo demo project> which shows how
-- to use it in your @Setup.hs@ Cabal build script.
--
-- It could also work pretty well for throwaway scripts.
