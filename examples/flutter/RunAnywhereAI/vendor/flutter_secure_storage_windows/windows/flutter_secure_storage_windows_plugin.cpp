#include "flutter_secure_storage_windows_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>
#include <wincred.h>
#include <atlstr.h>
#include <ShlObj_core.h>
#include <sys/stat.h>
#include <errno.h>
#include <direct.h>
#include <bcrypt.h>

// For getPlatformVersion; remove unless needed for your plugin implementation.
#include <VersionHelpers.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <map>
#include <memory>
#include <sstream>
#include <iostream>
#include <fstream>
#include <string>
#include <regex>

#pragma comment(lib, "version.lib")
#pragma comment(lib, "bcrypt.lib")

namespace
{

  class FlutterSecureStorageWindowsPlugin : public flutter::Plugin
  {
  public:
    static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

    FlutterSecureStorageWindowsPlugin();

    virtual ~FlutterSecureStorageWindowsPlugin();

  private:
    // Called when a method is called on this plugin's channel from Dart.
    void HandleMethodCall(
        const flutter::MethodCall<flutter::EncodableValue> &method_call,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

    // Retrieves the value passed to the given param.
    std::optional<std::string> GetStringArg(
        const std::string &param,
        const flutter::EncodableMap *args);

    // Derive the key for a value given a method argument map.
    std::optional<std::string> FlutterSecureStorageWindowsPlugin::GetValueKey(const flutter::EncodableMap *args);

    // Removes prefix of the given storage key.
    // 
    // The prefix (defined by ELEMENT_PREFERENCES_KEY_PREFIX) is added automatically when writing to storage,
    // to distinguish values that are written by this plugin from values that are not.
    std::string RemoveKeyPrefix(const std::string &key);

    // Gets the string name for the given int error code
    std::string GetErrorString(const DWORD &error_code);
    // Get string name of ntstatus
    std::string NtStatusToString(const CHAR* operation, NTSTATUS status);

    DWORD GetApplicationSupportPath(std::wstring& path);

    std::wstring SanitizeDirString(std::wstring string);

    bool PathExists(const std::wstring& path);

    bool MakePath(const std::wstring& path);

    PBYTE GetEncryptionKey();

    // Stores the given value under the given key.
    void Write(const std::string &key, const std::string &val);

    std::optional<std::string> Read(const std::string &key);

    flutter::EncodableMap ReadAll();

    void Delete(const std::string &key);

    void DeleteAll();

    bool ContainsKey(const std::string &key);
  };

  const std::string ELEMENT_PREFERENCES_KEY_PREFIX = SECURE_STORAGE_KEY_PREFIX;
  const int ELEMENT_PREFERENCES_KEY_PREFIX_LENGTH = (sizeof SECURE_STORAGE_KEY_PREFIX) - 1;

  // this string is used to filter the credential storage so that only the values written
  // by this plugin shows up.
  const CA2W CREDENTIAL_FILTER((ELEMENT_PREFERENCES_KEY_PREFIX + '*').c_str());

  static inline void rtrim(std::wstring& s) {
      s.erase(std::find_if(s.rbegin(), s.rend(), [](wchar_t ch) {
          return !std::isspace(ch);
          }).base(), s.end());
  }

  // static
  void FlutterSecureStorageWindowsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarWindows *registrar)
  {
    auto channel =
        std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            registrar->messenger(), "plugins.it_nomads.com/flutter_secure_storage",
            &flutter::StandardMethodCodec::GetInstance());

    auto plugin = std::make_unique<FlutterSecureStorageWindowsPlugin>();

    channel->SetMethodCallHandler(
        [plugin_pointer = plugin.get()](const auto &call, auto result)
        {
          plugin_pointer->HandleMethodCall(call, std::move(result));
        });

    registrar->AddPlugin(std::move(plugin));
  }

  FlutterSecureStorageWindowsPlugin::FlutterSecureStorageWindowsPlugin() {}

  FlutterSecureStorageWindowsPlugin::~FlutterSecureStorageWindowsPlugin() {}

  std::optional<std::string> FlutterSecureStorageWindowsPlugin::GetValueKey(const flutter::EncodableMap *args)
  {
    auto key = this->GetStringArg("key", args);
    if (key.has_value())
      return ELEMENT_PREFERENCES_KEY_PREFIX + key.value();
    return std::nullopt;
  }

  std::string FlutterSecureStorageWindowsPlugin::RemoveKeyPrefix(const std::string& key)
  {
    return key.substr(ELEMENT_PREFERENCES_KEY_PREFIX_LENGTH);
  }

  std::optional<std::string> FlutterSecureStorageWindowsPlugin::GetStringArg(
      const std::string &param,
      const flutter::EncodableMap *args)
  {
    auto p = args->find(param);
    if (p == args->end())
      return std::nullopt;
    return std::get<std::string>(p->second);
  }

  std::string FlutterSecureStorageWindowsPlugin::GetErrorString(const DWORD &error_code)
  {
    switch (error_code)
    {
    case ERROR_NO_SUCH_LOGON_SESSION:
      return "ERROR_NO_SUCH_LOGIN_SESSION";
    case ERROR_INVALID_FLAGS:
      return "ERROR_INVALID_FLAGS";
    case ERROR_BAD_USERNAME:
      return "ERROR_BAD_USERNAME";
    case SCARD_E_NO_READERS_AVAILABLE:
      return "SCARD_E_NO_READERS_AVAILABLE";
    case SCARD_E_NO_SMARTCARD:
      return "SCARD_E_NO_SMARTCARD";
    case SCARD_W_REMOVED_CARD:
      return "SCARD_W_REMOVED_CARD";
    case SCARD_W_WRONG_CHV:
      return "SCARD_W_WRONG_CHV";
    case ERROR_INVALID_PARAMETER:
      return "ERROR_INVALID_PARAMETER";
    default:
      return "UNKNOWN_ERROR";
    }
  }

  std::string FlutterSecureStorageWindowsPlugin::NtStatusToString(const CHAR* operation, NTSTATUS status)
  {
      std::ostringstream oss;
      oss << operation << ", 0x" << std::hex << status;

      switch (status)
      {
      case 0xc0000000:
          oss << " (STATUS_SUCCESS)";
          break;
      case 0xC0000008:
          oss << " (STATUS_INVALID_HANDLE)";
          break;
      case 0xc000000d:
          oss << " (STATUS_INVALID_PARAMETER)";
          break;
      case 0xc00000bb:
          oss << " (STATUS_NOT_SUPPORTED)";
          break;
      case 0xC0000225:
          oss << " (STATUS_NOT_FOUND)";
          break;
      }
      return oss.str();
  }

  DWORD FlutterSecureStorageWindowsPlugin::GetApplicationSupportPath(std::wstring &path)
  {
      std::wstring companyName;
      std::wstring productName;
      TCHAR nameBuffer[MAX_PATH + 1]{};
      char* infoBuffer;
      DWORD versionInfoSize;
      DWORD resVal;
      UINT queryLen;
      LPVOID queryVal;
      LPWSTR appdataPath;
      std::wostringstream stream;

      SHGetKnownFolderPath(FOLDERID_RoamingAppData,KF_FLAG_DEFAULT,NULL,&appdataPath);
      
      if (nameBuffer == NULL) {
          return ERROR_OUTOFMEMORY;
      }

      resVal = GetModuleFileName(NULL,nameBuffer,MAX_PATH);
      if (resVal == 0) {
          return GetLastError();
      }

      versionInfoSize = GetFileVersionInfoSize(nameBuffer, NULL);
      if (versionInfoSize != 0) {
          infoBuffer = (char*) calloc(versionInfoSize,sizeof(char));
          if (infoBuffer == NULL) {
              return ERROR_OUTOFMEMORY;
          }
          if (GetFileVersionInfo(nameBuffer, 0, versionInfoSize, infoBuffer) == 0) {
              free(infoBuffer);
              infoBuffer = NULL;
          }
          else {

              if (VerQueryValue(infoBuffer, TEXT("\\StringFileInfo\\040904e4\\CompanyName"), &queryVal, &queryLen) != 0) {
                  companyName = SanitizeDirString(std::wstring((const TCHAR*)queryVal));
              }
              else if (VerQueryValue(infoBuffer, TEXT("\\StringFileInfo\\040904b0\\CompanyName"), &queryVal, &queryLen) != 0) {
                  companyName = SanitizeDirString(std::wstring((const TCHAR*)queryVal));
              }
              else {
                  companyName = L"placeholder_company";
              }
              if (VerQueryValue(infoBuffer, TEXT("\\StringFileInfo\\040904e4\\ProductName"), &queryVal, &queryLen) != 0) {
                  productName = SanitizeDirString(std::wstring((const TCHAR*)queryVal));
              }
              else if (VerQueryValue(infoBuffer, TEXT("\\StringFileInfo\\040904b0\\ProductName"), &queryVal, &queryLen) != 0) {
                  productName = SanitizeDirString(std::wstring((const TCHAR*)queryVal));
              }
              else {
                  productName = L"placeholder_product";
              }
          }
          stream << appdataPath << "\\" << companyName << "\\" << productName;
          path = stream.str();
      }
      else {
          return GetLastError();
      }
      return ERROR_SUCCESS;

  }

  std::wstring FlutterSecureStorageWindowsPlugin::SanitizeDirString(std::wstring string)
  {
      std::wstring illegalChars = L"\\/:?\"<>|";
      for (auto it = string.begin(); it < string.end(); ++it) {
          if (illegalChars.find(*it) != std::wstring::npos) {
              *it = L'_';
          }
      }
      rtrim(string);
      return string;
  }

  bool FlutterSecureStorageWindowsPlugin::PathExists(const std::wstring& path)
  {
      struct _stat info;
      if (_wstat(path.c_str(), &info) != 0) {
          return false;
      }
      return (info.st_mode & _S_IFDIR) != 0;
  }

  bool FlutterSecureStorageWindowsPlugin::MakePath(const std::wstring& path)
  {
      int ret = _wmkdir(path.c_str());
      if (ret == 0) {
          return true;
      }
      switch (errno) {
      case ENOENT:
        {
          size_t pos = path.find_last_of('/');
          if (pos == std::wstring::npos)
              pos = path.find_last_of('\\');
          if (pos == std::wstring::npos)
              return false;
          if (!MakePath(path.substr(0, pos)))
              return false; 
        }
        return 0 == _wmkdir(path.c_str());
      case EEXIST:
          return PathExists(path);
      default:
          return false;
      }
  }

  PBYTE FlutterSecureStorageWindowsPlugin::GetEncryptionKey()
  {
      const size_t KEY_SIZE = 16;
      DWORD credError = 0;
      PBYTE AesKey;
      PCREDENTIALW pcred;
      CA2W target_name(("key_" + ELEMENT_PREFERENCES_KEY_PREFIX).c_str());

      AesKey = (PBYTE)HeapAlloc(GetProcessHeap(), 0, KEY_SIZE);
      if (NULL == AesKey) {
          return NULL;
      }

      bool ok = CredReadW(target_name.m_psz, CRED_TYPE_GENERIC, 0, &pcred);
      if (ok) {
          if (pcred->CredentialBlobSize != KEY_SIZE) {
              CredFree(pcred);
              CredDeleteW(target_name.m_psz, CRED_TYPE_GENERIC, 0);
              goto NewKey;
          }
          memcpy(AesKey, pcred->CredentialBlob, KEY_SIZE);
          CredFree(pcred);
          return AesKey;
      }
      credError = GetLastError();
      if (credError != ERROR_NOT_FOUND) {
          return NULL;
      }
  NewKey:
      if (BCryptGenRandom(NULL, AesKey, KEY_SIZE, BCRYPT_USE_SYSTEM_PREFERRED_RNG) != ERROR_SUCCESS) {
          return NULL;
      }
      CREDENTIALW cred = { 0 };
      cred.Type = CRED_TYPE_GENERIC;
      cred.TargetName = target_name.m_psz;
      cred.CredentialBlobSize = KEY_SIZE;
      cred.CredentialBlob = AesKey;
      cred.Persist = CRED_PERSIST_LOCAL_MACHINE;

      ok = CredWriteW(&cred, 0);
      if (!ok) {
          std::cerr << "Failed to write encryption key" << std::endl;
          return NULL;
      }
      return AesKey;
  }

  void FlutterSecureStorageWindowsPlugin::HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
  {
    auto method = method_call.method_name();
    const auto *args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    std::wstring path;
    if (GetApplicationSupportPath(path) != ERROR_SUCCESS) {
        result->Error("Exception occurred", "GetApplicationSupportPath");
        return;
    }
    try
    {
      if (method == "write")
      {
        auto key = this->GetValueKey(args);
        auto val = this->GetStringArg("value", args);
        if (key.has_value())
        {
          if (val.has_value())
            this->Write(key.value(), val.value());
          else
            this->Delete(key.value());
          result->Success();
        }
        else
        {
          result->Error("Exception occurred", "write");
        }
      }
      else if (method == "read")
      {
        auto key = this->GetValueKey(args);
        if (key.has_value())
        {
          auto val = this->Read(key.value());
          if (val.has_value())
            result->Success(flutter::EncodableValue(val.value()));
          else
            result->Success();
        }
        else
        {
          result->Error("Exception occurred", "read");
        }
      }
      else if (method == "readAll")
      {
        auto creds = this->ReadAll();
        result->Success(flutter::EncodableValue(creds));
      }
      else if (method == "delete")
      {
        auto key = this->GetValueKey(args);
        if (key.has_value())
        {
          this->Delete(key.value());
          result->Success();
        }
        else
        {
          result->Error("Exception occurred", "delete");
        }
      }
      else if (method == "deleteAll")
      {
        this->DeleteAll();
        result->Success();
      }
      else if (method == "containsKey")
      {
        auto key = this->GetValueKey(args);
        if (key.has_value())
        {
          auto contains_key = this->ContainsKey(key.value());
          result->Success(flutter::EncodableValue(contains_key));
        }
        else
        {
          result->Error("Exception occurred", "containsKey");
        }
      }
      else
      {
        result->NotImplemented();
      }
    }
    catch (DWORD e)
    {
      auto str_code = this->GetErrorString(e);
      result->Error("Exception encountered: " + str_code, method);
    }
  }

  void FlutterSecureStorageWindowsPlugin::Write(const std::string &key, const std::string &val)
  {
      //The recommended size for AES-GCM IV is 12 bytes
      const DWORD NONCE_SIZE = 12;
      const DWORD KEY_SIZE = 16;

      NTSTATUS status;
      BCRYPT_ALG_HANDLE algo = NULL;
      BCRYPT_KEY_HANDLE keyHandle = NULL;
      DWORD bytesWritten = 0,
          ciphertextSize = 0;
      PBYTE ciphertext = NULL,
          iv = (PBYTE)HeapAlloc(GetProcessHeap(), 0, NONCE_SIZE),
          encryptionKey = GetEncryptionKey();
      BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO authInfo{};
      BCRYPT_AUTH_TAG_LENGTHS_STRUCT authTagLengths{};
      std::basic_ofstream<BYTE> fs;
      std::wstring appSupportPath;
      std::string error;

      if (iv == NULL) {
          error = "IV HeapAlloc Failed";
          goto err;
      }
      if (encryptionKey == NULL) {
          error = "encryptionKey is NULL";
          goto err;
      }
      status = BCryptOpenAlgorithmProvider(&algo, BCRYPT_AES_ALGORITHM, NULL, 0);
      if (!BCRYPT_SUCCESS(status)) {
          error = NtStatusToString("BCryptOpenAlgorithmProvider", status);
          goto err;
      }
      status = BCryptSetProperty(algo, BCRYPT_CHAINING_MODE, (PUCHAR)BCRYPT_CHAIN_MODE_GCM, sizeof(BCRYPT_CHAIN_MODE_GCM), 0);
      if (!BCRYPT_SUCCESS(status)) {
          error = NtStatusToString("BCryptSetProperty", status);
          goto err;
      }
      status = BCryptGetProperty(algo, BCRYPT_AUTH_TAG_LENGTH, (PBYTE)&authTagLengths, sizeof(BCRYPT_AUTH_TAG_LENGTHS_STRUCT), &bytesWritten, 0);
      if (!BCRYPT_SUCCESS(status)) {
          error = NtStatusToString("BCryptGetProperty", status);
          goto err;
      }
      BCRYPT_INIT_AUTH_MODE_INFO(authInfo);
      authInfo.pbNonce = (PUCHAR)HeapAlloc(GetProcessHeap(), 0, NONCE_SIZE);
      if (authInfo.pbNonce == NULL) {
          error = "pbNonce HeapAlloc Failed";
          goto err;
      }
      authInfo.cbNonce = NONCE_SIZE;
      status = BCryptGenRandom(NULL, iv, authInfo.cbNonce, BCRYPT_USE_SYSTEM_PREFERRED_RNG);
      if (!BCRYPT_SUCCESS(status)) {
          error = NtStatusToString("BCryptGenRandom", status);
          goto err;
      }
      //copy the original IV into the authInfo, we can't write the IV directly into the authInfo because it will change after calling BCryptEncrypt and we still need to write the IV to file
      memcpy(authInfo.pbNonce, iv, authInfo.cbNonce);
      //We do not use additional authenticated data
      authInfo.pbAuthData = NULL;
      authInfo.cbAuthData = 0;
      //Make space for the authentication tag
      authInfo.pbTag = (PUCHAR)HeapAlloc(GetProcessHeap(), 0, authTagLengths.dwMaxLength);
      if (authInfo.pbTag == NULL) {
          error = "pbTag HeapAlloc Failed";
          goto err;
      }
      authInfo.cbTag = authTagLengths.dwMaxLength;
      status = BCryptGenerateSymmetricKey(algo, &keyHandle, NULL, 0, encryptionKey, KEY_SIZE, 0);
      if (!BCRYPT_SUCCESS(status)) {
          error = NtStatusToString("BCryptGenerateSymmetricKey", status);
          goto err;
      }
      //First call to BCryptEncrypt to get size of ciphertext
      status = BCryptEncrypt(keyHandle, (PUCHAR)val.c_str(), (ULONG)val.length() + 1, (PVOID)&authInfo, NULL, 0, NULL, 0, &bytesWritten, 0);
      if (!BCRYPT_SUCCESS(status)) {
          error = NtStatusToString("BCryptEncrypt1", status);
          goto err;
      }
      ciphertextSize = bytesWritten;
      ciphertext = (PBYTE)HeapAlloc(GetProcessHeap(), 0, ciphertextSize);
      if (ciphertext == NULL) {
          error = "CipherText HeapAlloc failed";
          goto err;
      }
      //Actual encryption
      status = BCryptEncrypt(keyHandle, (PUCHAR)val.c_str(), (ULONG)val.length() + 1, (PVOID)&authInfo, NULL, 0, ciphertext, ciphertextSize, &bytesWritten, 0);
      if (!BCRYPT_SUCCESS(status)) {
          error = NtStatusToString("BCryptEncrypt2", status);
          goto err;
      }
      GetApplicationSupportPath(appSupportPath);
      if (!PathExists(appSupportPath)) {
          MakePath(appSupportPath);
      }
      fs = std::basic_ofstream<BYTE>(appSupportPath + L"\\" + std::wstring(key.begin(), key.end()) + L".secure", std::ios::binary | std::ios::trunc);
      if (!fs) {
          error = "Failed to open output stream";
          goto err;
      }
      fs.write(iv, NONCE_SIZE);
      fs.write(authInfo.pbTag, authInfo.cbTag);
      fs.write(ciphertext, ciphertextSize);
      fs.close();
      HeapFree(GetProcessHeap(), 0, iv);
      HeapFree(GetProcessHeap(), 0, encryptionKey);
      HeapFree(GetProcessHeap(), 0, authInfo.pbNonce);
      HeapFree(GetProcessHeap(), 0, authInfo.pbTag);
      HeapFree(GetProcessHeap(), 0, ciphertext);
      return;
  err:
      if (iv) {
          HeapFree(GetProcessHeap(), 0, iv);
      }
      if (encryptionKey) {
          HeapFree(GetProcessHeap(), 0, encryptionKey);
      }
      if (authInfo.pbNonce) {
          HeapFree(GetProcessHeap(), 0, authInfo.pbNonce);
      }
      if (authInfo.pbTag) {
          HeapFree(GetProcessHeap(), 0, authInfo.pbTag);
      }
      if (ciphertext) {
          HeapFree(GetProcessHeap(), 0, ciphertext);
      }
      throw std::runtime_error(error);
  }

  std::optional<std::string> FlutterSecureStorageWindowsPlugin::Read(const std::string &key)
  {
      const DWORD NONCE_SIZE = 12;
      const DWORD KEY_SIZE = 16;

      NTSTATUS status;
      BCRYPT_ALG_HANDLE algo = NULL;
      BCRYPT_KEY_HANDLE keyHandle = NULL;
      BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO authInfo{};
      BCRYPT_AUTH_TAG_LENGTHS_STRUCT authTagLengths{};

      PBYTE encryptionKey = GetEncryptionKey(),
          ciphertext = NULL,
          fileBuffer = NULL,
          plaintext = NULL;
      DWORD plaintextSize = 0,
          bytesWritten = 0,
          ciphertextSize = 0;
      std::wstring appSupportPath;
      std::basic_ifstream<BYTE> fs;
      std::streampos fileSize;
      std::optional<std::string> returnVal = std::nullopt;

      if (encryptionKey == NULL) {
          std::cerr << "encryptionKey is NULL" << std::endl;
          goto cleanup;
      }
      GetApplicationSupportPath(appSupportPath);
      if (!PathExists(appSupportPath)) {
          MakePath(appSupportPath);
      }
      //Read full file into a buffer
      fs = std::basic_ifstream<BYTE>(appSupportPath + L"\\" + std::wstring(key.begin(), key.end()) + L".secure", std::ios::binary);
      if (!fs.good()) {
          //Backwards comp.
          PCREDENTIALW pcred;
          CA2W target_name(key.c_str());
          bool ok = CredReadW(target_name.m_psz, CRED_TYPE_GENERIC, 0, &pcred);
          if (ok)
          {
              auto val = std::string((char*)pcred->CredentialBlob);
              CredFree(pcred);
              returnVal = val;
          }
          goto cleanup;
      }
      fs.unsetf(std::ios::skipws);
      fs.seekg(0, std::ios::end);
      fileSize = fs.tellg();
      fs.seekg(0, std::ios::beg);
      fileBuffer = (PBYTE)HeapAlloc(GetProcessHeap(), 0, fileSize);
      if (NULL == fileBuffer) {
          std::cerr << "fileBuffer HeapAlloc failed" << std::endl;
          goto cleanup;
      }
      fs.read(fileBuffer, fileSize);
      fs.close();

      status = BCryptOpenAlgorithmProvider(&algo, BCRYPT_AES_ALGORITHM, NULL, 0);
      if (!BCRYPT_SUCCESS(status)) {
          std::cerr << NtStatusToString("BCryptOpenAlgorithmProvider", status) << std::endl;
          goto cleanup;
      }
      status = BCryptSetProperty(algo, BCRYPT_CHAINING_MODE, (PUCHAR)BCRYPT_CHAIN_MODE_GCM, sizeof(BCRYPT_CHAIN_MODE_GCM), 0);
      if (!BCRYPT_SUCCESS(status)) {
          std::cerr << NtStatusToString("BCryptOpenAlgorithmProvider", status) << std::endl;
          goto cleanup;
      }
      status = BCryptGetProperty(algo, BCRYPT_AUTH_TAG_LENGTH, (PBYTE)&authTagLengths, sizeof(BCRYPT_AUTH_TAG_LENGTHS_STRUCT), &bytesWritten, 0);
      if (!BCRYPT_SUCCESS(status)) {
          std::cerr << NtStatusToString("BCryptGetProperty", status) << std::endl;
          goto cleanup;
      }

      BCRYPT_INIT_AUTH_MODE_INFO(authInfo);
      authInfo.pbNonce = (PUCHAR)HeapAlloc(GetProcessHeap(), 0, NONCE_SIZE);
      if (authInfo.pbNonce == NULL) {
          std::cerr << "pbNonce HeapAlloc Failed" << std::endl;
          goto cleanup;
      }
      authInfo.cbNonce = NONCE_SIZE;
      //Check if file is at least long enough for iv and authentication tag
      if (fileSize <= static_cast<long long>(NONCE_SIZE) + authTagLengths.dwMaxLength) {
          std::cerr << "File is too small" << std::endl;
          goto cleanup;
      }
      authInfo.pbTag = (PUCHAR)HeapAlloc(GetProcessHeap(), 0, authTagLengths.dwMaxLength);
      if (authInfo.pbTag == NULL) {
          std::cerr << "pbTag HeapAlloc Failed" << std::endl;
          goto cleanup;
      }
      ciphertextSize = (DWORD)fileSize - NONCE_SIZE - authTagLengths.dwMaxLength;
      ciphertext = (PBYTE)HeapAlloc(GetProcessHeap(), 0, ciphertextSize);
      if (ciphertext == NULL) {
          std::cerr << "ciphertext HeapAlloc failed" << std::endl;
          goto cleanup;
      }
      //Copy different parts needed for decryption from filebuffer
#pragma warning(push)
#pragma warning(disable:6385)
      memcpy(authInfo.pbNonce, fileBuffer, NONCE_SIZE);
#pragma warning(pop)
      memcpy(authInfo.pbTag, &fileBuffer[NONCE_SIZE], authTagLengths.dwMaxLength);
      memcpy(ciphertext, &fileBuffer[NONCE_SIZE + authTagLengths.dwMaxLength], ciphertextSize);
      authInfo.cbTag = authTagLengths.dwMaxLength;

      status = BCryptGenerateSymmetricKey(algo, &keyHandle, NULL, 0, encryptionKey, KEY_SIZE, 0);
      if (!BCRYPT_SUCCESS(status)) {
          std::cerr << NtStatusToString("BCryptGenerateSymmetricKey", status) << std::endl;
          goto cleanup;
      }
      //First call is to determine size of plaintext
      status = BCryptDecrypt(keyHandle, ciphertext, ciphertextSize, (PVOID)&authInfo, NULL, 0, NULL, 0, &bytesWritten, 0);
      if (!BCRYPT_SUCCESS(status)) {
          std::cerr << NtStatusToString("BCryptDecrypt1", status) << std::endl;
          goto cleanup;
      }
      plaintextSize = bytesWritten;
      plaintext = (PBYTE)HeapAlloc(GetProcessHeap(), 0, plaintextSize);
      if (NULL == plaintext) {
          std::cerr << "plaintext HeapAlloc failed" << std::endl;
          goto cleanup;
      }
      //Actuual decryption
      status = BCryptDecrypt(keyHandle, ciphertext, ciphertextSize, (PVOID)&authInfo, NULL, 0, plaintext, plaintextSize, &bytesWritten, 0);
      if (!BCRYPT_SUCCESS(status)) {
          std::cerr << NtStatusToString("BCryptDecrypt2", status) << std::endl;
          goto cleanup;
      }
      returnVal = (char*)plaintext;
  cleanup:
      if (encryptionKey) {
          HeapFree(GetProcessHeap(), 0, encryptionKey);
      }
      if (ciphertext) {
          HeapFree(GetProcessHeap(), 0, ciphertext);
      }
      if (plaintext) {
          HeapFree(GetProcessHeap(), 0, plaintext);
      }
      if (fileBuffer) {
          HeapFree(GetProcessHeap(), 0, fileBuffer);
      }
      if (authInfo.pbNonce) {
          HeapFree(GetProcessHeap(), 0, authInfo.pbNonce);
      }
      if (authInfo.pbTag) {
          HeapFree(GetProcessHeap(), 0, authInfo.pbTag);
      }
      return returnVal;
  }

  flutter::EncodableMap FlutterSecureStorageWindowsPlugin::ReadAll()
  {
      WIN32_FIND_DATA searchRes;
      HANDLE hFile;
      std::wstring appSupportPath;

      GetApplicationSupportPath(appSupportPath);
      if (!PathExists(appSupportPath)) {
          MakePath(appSupportPath);
      }
      hFile = FindFirstFile((appSupportPath + L"\\*.secure").c_str(), &searchRes);
      if (hFile == INVALID_HANDLE_VALUE) {
          return flutter::EncodableMap();
      }

      flutter::EncodableMap creds;

      do {
          std::wstring fileName(searchRes.cFileName);
          size_t pos = fileName.find(L".secure");
          fileName.erase(pos, 7);
          char* out = new char[fileName.length() + 1];
          size_t charsConverted = 0;
          wcstombs_s(&charsConverted, out, fileName.length() + 1, fileName.c_str(), fileName.length() + 1);
          std::optional<std::string> val = this->Read(out);
          auto key = this->RemoveKeyPrefix(out);
          if (val.has_value()) {
              creds[key] = val.value();
              continue;
          }
      } while (FindNextFile(hFile, &searchRes) != 0);

    //Backwards comp.
    PCREDENTIALW* pcreds;
    DWORD cred_count = 0;

    bool ok = CredEnumerateW(CREDENTIAL_FILTER.m_psz, 0, &cred_count, &pcreds);
    if (!ok)
    {
        return creds;
    }
    for (DWORD i = 0; i < cred_count; i++)
    {
      auto pcred = pcreds[i];
      std::string target_name = CW2A(pcred->TargetName);
      auto val = std::string((char*)pcred->CredentialBlob);
      auto key = this->RemoveKeyPrefix(target_name);
      //If the key exists then data was already read from a file, which implies that the data read from the credential system is outdated
      if (creds.find(key) == creds.end()) {
          creds[key] = val;
      }
    }

    CredFree(pcreds);

    return creds;
  }

  void FlutterSecureStorageWindowsPlugin::Delete(const std::string &key)
  {
      std::wstring appSupportPath;
      GetApplicationSupportPath(appSupportPath);
      auto wstr = std::wstring(key.begin(), key.end());
      BOOL ok = DeleteFile((appSupportPath + L"\\" + wstr + L".secure").c_str());
      if (!ok) {
          DWORD error = GetLastError();
          if (error != ERROR_FILE_NOT_FOUND && error != ERROR_PATH_NOT_FOUND) {
              throw error;
          }
      }

    //Backwards comp.
    ok = CredDeleteW(wstr.c_str(), CRED_TYPE_GENERIC, 0);
    if (!ok)
    {
      auto error = GetLastError();

      // Silently ignore if we try to delete a key that doesn't exist
      if (error == ERROR_NOT_FOUND)
        return;

      throw error;
    }
  }

  void FlutterSecureStorageWindowsPlugin::DeleteAll()
  {

      WIN32_FIND_DATA searchRes;
      HANDLE hFile;
      std::wstring appSupportPath;

      GetApplicationSupportPath(appSupportPath);
      if (!PathExists(appSupportPath)) {
          MakePath(appSupportPath);
      }
      hFile = FindFirstFile((appSupportPath + L"\\*.secure").c_str(), &searchRes);
      if (hFile == INVALID_HANDLE_VALUE) {
          return;
      }
      do {
          std::wstring fileName(searchRes.cFileName);
          BOOL ok = DeleteFile((appSupportPath + L"\\" + fileName).c_str());
          if (!ok) {
              DWORD error = GetLastError();
              if (error != ERROR_FILE_NOT_FOUND) {
                  throw error;
              }
          }
      } while (FindNextFile(hFile, &searchRes) != 0);

    //Backwards comp.
    PCREDENTIALW* pcreds;
    DWORD cred_count = 0;
    
    bool read_ok = CredEnumerateW(CREDENTIAL_FILTER.m_psz, 0, &cred_count, &pcreds);
    if (!read_ok)
    {
      auto error = GetLastError();
      if (error == ERROR_NOT_FOUND)
        // No credentials to delete
        return;
      throw error;
    }

    for (DWORD i = 0; i < cred_count; i++)
    {
      auto pcred = pcreds[i];
      auto target_name = pcred->TargetName;
      
      bool delete_ok = CredDeleteW(target_name, CRED_TYPE_GENERIC, 0);
      if (!delete_ok)
      {
        throw GetLastError();
      }
    }

    CredFree(pcreds);
  }

  bool FlutterSecureStorageWindowsPlugin::ContainsKey(const std::string &key)
  {
      std::wstring appSupportPath;
      GetApplicationSupportPath(appSupportPath);
      std::wstring wstr = std::wstring(key.begin(), key.end());
      if (INVALID_FILE_ATTRIBUTES == GetFileAttributes((appSupportPath + L"\\" + wstr + L".secure").c_str())) {
          //Backwards comp.
          PCREDENTIALW pcred;
          CA2W target_name(key.c_str());

          bool ok = CredReadW(target_name.m_psz, CRED_TYPE_GENERIC, 0, &pcred);
          if (ok) return true;

          auto error = GetLastError();
          if (error == ERROR_NOT_FOUND)
              return false;
          throw error;
      }
      return true;
  }
} // namespace

void FlutterSecureStorageWindowsPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar)
{
  FlutterSecureStorageWindowsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
