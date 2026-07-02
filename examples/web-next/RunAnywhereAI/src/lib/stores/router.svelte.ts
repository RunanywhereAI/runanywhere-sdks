export type Route = 'chat' | 'voice' | 'more' | 'settings' | 'vision' | 'rag' | 'tts' | 'stt';

class Router {
  active = $state<Route>('chat');

  go(route: Route): void {
    this.active = route;
  }
}

export const router = new Router();
