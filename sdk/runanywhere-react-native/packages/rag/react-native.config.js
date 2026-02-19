module.exports = {
  dependency: {
    platforms: {
      android: {
        sourceDir: './android',
        packageImportPath: 'import com.margelo.nitro.runanywhere.rag.RunAnywhereRAGPackage;',
        packageInstance: 'new RunAnywhereRAGPackage()',
      },
      ios: {
        podspecPath: './RunAnywhereRAG.podspec',
      },
    },
  },
};
