import { taskpool } from '@kit.ArkTS';
import { logger } from './Logger';

const TAG: string = 'JsonSerializeUtils';

/**
 * 工作线程内的序列化函数。
 * 必须是顶层函数 + @Concurrent 装饰，不能依赖闭包或 this。
 * 参数通过 taskpool 序列化传递，支持复杂嵌套对象。
 */
@Concurrent
function serializeInWorker(obj: Object): string {
  return JSON.stringify(obj, null, 2);
}

/**
 * 异步序列化大对象（>10KB），避免阻塞主线程。
 * 小对象（<10KB）请直接使用 JSON.stringify，线程切换开销大于序列化耗时。
 *
 * @param obj 待序列化对象
 * @returns 格式化后的 JSON 字符串
 */
export async function serializeAsync(obj: Object): Promise<string> {
  try {
    const task: taskpool.Task = new taskpool.Task(serializeInWorker, obj);
    return await taskpool.execute(task) as string;
  } catch (error) {
    logger.error(TAG, `TaskPool 序列化失败，回退主线程: ${String(error)}`);
    return JSON.stringify(obj, null, 2);
  }
}
