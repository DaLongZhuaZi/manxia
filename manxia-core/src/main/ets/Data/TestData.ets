// 文件路径: src/main/ets/Data/TestData.ets
/**
 * 测试数据定义
 * 提供测试页面所需的数据结构和默认数据
 */

/**
 * 测试项目接口
 */
export interface TestItem {
  id: string;
  title: string;
  description: string;
  icon: string;
  routeName: string;
  isAvailable: boolean;
  category: string;
}

/**
 * 测试分类类型
 */
export type TestCategory = '全部' | '系统测试' | '功能测试' | '演示页面';

/**
 * 测试数据集合
 */
export interface TestDataCollection {
  categories: TestCategory[];
  items: TestItem[];
}

/**
 * 默认测试数据
 */
export const testData: TestDataCollection = {
  categories: ['全部', '系统测试', '功能测试', '演示页面'],
  items: [
    {
      id: 'dummy_page',
      title: '组件展示页面',
      description: '展示各种系统组件和动画效果的标准页面',
      icon: '🎨',
      routeName: 'DummyPage',
      isAvailable: true,
      category: '演示页面'
    },
    {
      id: 'system_animation_demo',
      title: '系统动画演示',
      description: '展示所有系统动画效果和动画控制功能',
      icon: '🎬',
      routeName: 'SystemAnimationDemoPage',
      isAvailable: true,
      category: '演示页面'
    },
    {
      id: 'system_resource_demo',
      title: '系统资源展示',
      description: '展示系统颜色资源和文件资源的博物馆式页面',
      icon: '🏛️',
      routeName: 'SystemResourceDemoPage',
      isAvailable: true,
      category: '演示页面'
    },
    {
      id: 'hello_world',
      title: 'Hello World',
      description: '基础的Hello World测试页面',
      icon: '👋',
      routeName: 'HelloWorldPage',
      isAvailable: true,
      category: '系统测试'
    },
    {
      id: 'system_status',
      title: '系统状态',
      description: '显示系统运行状态和性能信息',
      icon: '📊',
      routeName: 'SystemStatusPage',
      isAvailable: true,
      category: '系统测试'
    }
  ]
};

/**
 * 根据分类获取测试项目
 * @param category 分类名称
 * @returns 过滤后的测试项目列表
 */
export function getTestItemsByCategory(category: TestCategory): TestItem[] {
  if (category === '全部') {
    return testData.items;
  }
  return testData.items.filter(item => item.category === category);
}

/**
 * 根据ID获取测试项目
 * @param id 测试项目ID
 * @returns 测试项目或undefined
 */
export function getTestItemById(id: string): TestItem | undefined {
  return testData.items.find(item => item.id === id);
}

/**
 * 搜索测试项目
 * @param query 搜索关键词
 * @returns 匹配的测试项目列表
 */
export function searchTestItems(query: string): TestItem[] {
  const searchLower = query.toLowerCase();
  return testData.items.filter(item => 
    item.title.toLowerCase().includes(searchLower) ||
    item.description.toLowerCase().includes(searchLower)
  );
}