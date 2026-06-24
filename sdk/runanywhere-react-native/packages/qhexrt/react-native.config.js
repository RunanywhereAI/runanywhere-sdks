module.exports = {
  dependency: {
    platforms: {
      android: {
        sourceDir: './android',
        packageImportPath: 'import com.margelo.nitro.runanywhere.qhexrt.RunAnywhereQHexRTPackage;',
        packageInstance: 'new RunAnywhereQHexRTPackage()',
      },
      ios: {},
    },
  },
};
