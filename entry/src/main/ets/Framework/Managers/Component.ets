// 文件路径: src/main/ets/Framework/Managers/Component.ts

/**
 * 所有组件的基类。
 * 每个组件实例都包含一个只读的componentId属性，
 * 在构造时由子类明确传入。
 */
export class Component {
  public readonly componentId: string;

  // 子类必须通过super()调用来初始化这个ID
  constructor(id: string) {
    this.componentId = id;
  }

  // 子类仍然需要定义静态ID，用于在其他地方引用类型
  public static readonly id: string;
}
