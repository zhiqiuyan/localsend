import { common } from '@kit.AbilityKit';

/** Holds the UIAbilityContext so non-UI layers can reach the sandbox filesystem and preferences. */
export class AppContext {
  private static ctx: common.UIAbilityContext | null = null;

  static set(ctx: common.UIAbilityContext): void {
    AppContext.ctx = ctx;
  }

  static get(): common.UIAbilityContext {
    if (AppContext.ctx === null) {
      throw new Error('AppContext has not been initialised');
    }
    return AppContext.ctx as common.UIAbilityContext;
  }

  static filesDir(): string {
    return AppContext.get().filesDir;
  }
}
