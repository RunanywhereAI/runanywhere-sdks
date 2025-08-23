# RunAnywhere Voice Demo - Angular

🚧 **Work in Progress** 🚧

An Angular demonstration of the RunAnywhere Voice SDK, showcasing enterprise-grade voice processing capabilities in web browsers.

## Status

This Angular demo application is currently under development and not yet functional. The implementation is planned to include:

- 🎤 **Real-time Voice Processing**: Complete VAD → STT → LLM → TTS pipeline
- ⚡ **Ultra-low Latency**: Target <500ms end-to-end response time
- 📊 **Performance Monitoring**: Real-time metrics dashboard
- ⚙️ **Configuration Panel**: Adjust models, voices, and features
- 🎨 **Angular Material UI**: Professional enterprise-grade components
- 📱 **Responsive Design**: Mobile-first responsive layout
- 🔒 **Enterprise Ready**: Dependency injection and robust architecture

## Current Issues

- ❌ Angular package not yet implemented in SDK
- ❌ Component architecture needs design
- ❌ Service layer integration pending
- ❌ Build configuration not established
- ❌ TypeScript modules need creation

## Planned Features

### Component Architecture
```
src/
├── components/
│   ├── voice-assistant/
│   │   ├── voice-assistant.component.ts
│   │   ├── voice-assistant.component.html
│   │   └── voice-assistant.component.scss
│   ├── settings-panel/
│   │   ├── settings-panel.component.ts
│   │   └── settings-panel.component.html
│   └── metrics-dashboard/
│       ├── metrics-dashboard.component.ts
│       └── metrics-dashboard.component.html
├── services/
│   ├── voice-pipeline.service.ts
│   ├── settings.service.ts
│   └── metrics.service.ts
└── types/
    └── demo.types.ts
```

### Angular Features
- **Dependency Injection**: Robust service architecture
- **RxJS Reactive Programming**: Observable-based state management
- **Angular Material**: Professional UI components
- **TypeScript**: Full type safety throughout
- **Standalone Components**: Modern Angular architecture
- **Signals**: Latest reactive primitives (Angular 16+)

## Development Status

This demo is currently **not implemented** and requires the following work:

1. **Create Angular Package**: Implement `@runanywhere/angular` SDK package
2. **Component Development**: Build Angular-specific voice components
3. **Service Layer**: Create injectable services for voice pipeline
4. **Material Integration**: Implement Angular Material UI
5. **Build Setup**: Configure Angular CLI and build process
6. **Testing Framework**: Set up Jasmine/Karma testing

## Quick Start (When Ready)

```bash
# Install dependencies (not available yet)
cd examples/web/angular-demo
pnpm install

# Start development server (not implemented)
ng serve

# Build for production (not implemented)
ng build --prod
```

## Architecture Plan

The Angular demo will leverage Angular's enterprise-grade features:

- **Services**: Injectable voice pipeline and configuration services
- **Components**: Standalone components with modern Angular patterns
- **RxJS**: Reactive state management with Observables
- **Material Design**: Professional UI with Angular Material
- **TypeScript**: Strict typing and interfaces
- **Dependency Injection**: Testable and maintainable architecture

## Technology Stack (Planned)

- **Angular**: 17+ with standalone components
- **Angular Material**: UI component library
- **RxJS**: Reactive programming
- **TypeScript**: 5.0+
- **Angular CLI**: Build tooling
- **Jasmine/Karma**: Testing framework

## Browser Support (Planned)

- Chrome 90+
- Firefox 90+
- Safari 15+
- Edge 90+

### Required Features
- WebAssembly support
- Web Audio API
- MediaDevices getUserMedia
- SharedArrayBuffer (for ONNX Runtime)

## Contributing

This demo is currently in early development phase. The Angular SDK package needs to be created first before this demo can be implemented.

## License

This demo is part of the RunAnywhere SDK project. See the main project license for details.
