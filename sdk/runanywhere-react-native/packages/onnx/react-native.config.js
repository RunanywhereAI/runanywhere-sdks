module.exports = {
  dependency: {
    platforms: {
      android: {
        sourceDir: './android',
        packageImportPath: 'import com.margelo.nitro.runanywhere.onnx.*;',
      },
      ios: {
        podspecPath: './ios/ONNXBackend.podspec',
      },
    },
  },
};
