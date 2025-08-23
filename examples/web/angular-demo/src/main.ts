import { bootstrapApplication } from '@angular/platform-browser';
import { AppComponent } from './app/app.component';
import { importProvidersFrom } from '@angular/core';
import { RunAnywhereVoiceModule } from '@runanywhere/angular';

bootstrapApplication(AppComponent, {
  providers: [
    importProvidersFrom(RunAnywhereVoiceModule)
  ]
}).catch(err => console.error(err));
