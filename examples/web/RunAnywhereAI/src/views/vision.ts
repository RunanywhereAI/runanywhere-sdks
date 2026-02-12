/**
 * Vision Tab - Image upload + VLM description, Image Generation
 * Matches iOS VisionHubView with NavigationLink list.
 */

import { showModelSelectionSheet } from '../components/model-selection';

let container: HTMLElement;

export function initVisionTab(el: HTMLElement): void {
  container = el;
  container.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-title">Vision</div>
      <div class="toolbar-actions"></div>
    </div>
    <div class="scroll-area" id="vision-content">
      <div class="feature-list">
        <div class="feature-row" id="vision-chat-btn">
          <div class="feature-icon" style="background:#8B5CF6;">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="22" height="22"><rect x="3" y="3" width="18" height="18" rx="2" ry="2"/><circle cx="8.5" cy="8.5" r="1.5"/><polyline points="21 15 16 10 5 21"/></svg>
          </div>
          <div class="feature-text">
            <h3>Vision Chat</h3>
            <p>Chat with images using photos or file uploads</p>
          </div>
        </div>
        <div class="feature-row" id="vision-gen-btn">
          <div class="feature-icon" style="background:#EC4899;">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="22" height="22"><rect x="3" y="3" width="18" height="18" rx="2"/><path d="M3 16l5-5 4 4 4-6 5 7"/></svg>
          </div>
          <div class="feature-text">
            <h3>Image Generation</h3>
            <p>Create images from text prompts</p>
          </div>
        </div>
      </div>
    </div>

    <!-- Vision Chat Sub-view -->
    <div class="sub-view" id="vision-chat-view">
      <div class="toolbar">
        <button class="back-btn" id="vision-chat-back">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="18" height="18"><polyline points="15 18 9 12 15 6"/></svg>
          Vision
        </button>
        <div class="toolbar-title">Vision Chat</div>
        <div class="toolbar-actions"></div>
      </div>
      <div class="scroll-area" style="display:flex;flex-direction:column;align-items:center;justify-content:center;gap:var(--space-xl);padding:var(--space-3xl);text-align:center;">
        <div style="font-size:60px;">&#128247;</div>
        <h3>Upload an Image</h3>
        <p style="color:var(--text-secondary);max-width:300px;">Drag and drop or click to upload an image, then ask questions about it.</p>
        <input type="file" id="vision-file-input" accept="image/*" style="display:none;">
        <button class="btn btn-primary" id="vision-upload-btn">Choose Image</button>
        <div id="vision-preview" style="display:none;max-width:300px;">
          <img id="vision-preview-img" style="max-width:100%;border-radius:var(--radius-lg);" />
        </div>
        <div class="chat-input-area" style="width:100%;max-width:400px;border-top:none;background:transparent;">
          <textarea class="chat-input" placeholder="Describe this image..." rows="1" disabled></textarea>
          <button class="send-btn" disabled>
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" width="18" height="18"><path d="M2.01 21L23 12 2.01 3 2 10l15 2-15 2z"/></svg>
          </button>
        </div>
      </div>
    </div>

    <!-- Image Generation Sub-view -->
    <div class="sub-view" id="vision-gen-view">
      <div class="toolbar">
        <button class="back-btn" id="vision-gen-back">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="18" height="18"><polyline points="15 18 9 12 15 6"/></svg>
          Vision
        </button>
        <div class="toolbar-title">Image Generation</div>
        <div class="toolbar-actions"></div>
      </div>
      <div class="scroll-area" style="display:flex;flex-direction:column;align-items:center;justify-content:center;gap:var(--space-xl);padding:var(--space-3xl);text-align:center;">
        <div style="font-size:60px;">&#127912;</div>
        <h3>Create Images</h3>
        <p style="color:var(--text-secondary);max-width:300px;">Describe the image you want to generate. Requires a Diffusion model (CoreML only, not yet available on Web).</p>
        <div style="display:flex;gap:var(--space-sm);flex-wrap:wrap;justify-content:center;">
          <button class="btn btn-sm">A sunset over mountains</button>
          <button class="btn btn-sm">A cute robot</button>
          <button class="btn btn-sm">Abstract art</button>
        </div>
        <textarea class="chat-input" placeholder="Describe your image..." rows="2" style="max-width:400px;width:100%;"></textarea>
        <button class="btn btn-primary" disabled>Generate (Backend not available)</button>
      </div>
    </div>
  `;

  // Navigation
  container.querySelector('#vision-chat-btn')!.addEventListener('click', () => {
    container.querySelector('#vision-chat-view')!.classList.add('active');
  });
  container.querySelector('#vision-gen-btn')!.addEventListener('click', () => {
    container.querySelector('#vision-gen-view')!.classList.add('active');
  });
  container.querySelector('#vision-chat-back')!.addEventListener('click', () => {
    container.querySelector('#vision-chat-view')!.classList.remove('active');
  });
  container.querySelector('#vision-gen-back')!.addEventListener('click', () => {
    container.querySelector('#vision-gen-view')!.classList.remove('active');
  });

  // File upload
  const fileInput = container.querySelector('#vision-file-input') as HTMLInputElement;
  container.querySelector('#vision-upload-btn')!.addEventListener('click', () => fileInput.click());
  fileInput.addEventListener('change', () => {
    const file = fileInput.files?.[0];
    if (file) {
      const preview = container.querySelector('#vision-preview') as HTMLElement;
      const img = container.querySelector('#vision-preview-img') as HTMLImageElement;
      img.src = URL.createObjectURL(file);
      preview.style.display = 'block';
    }
  });
}
