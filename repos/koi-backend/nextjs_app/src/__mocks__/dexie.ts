type RecordType = Record<string, unknown>;

function compareValues(leftValue: unknown, rightValue: unknown): number {
  if (leftValue instanceof Date && rightValue instanceof Date) {
    return leftValue.getTime() - rightValue.getTime();
  }

  return String(leftValue ?? '').localeCompare(String(rightValue ?? ''));
}

class MockCollection<T extends RecordType> {
  constructor(
    protected readonly source: T[],
    protected readonly predicate: (record: T) => boolean = () => true,
  ) {}

  protected snapshot(): T[] {
    return this.source.filter(this.predicate);
  }

  async first(): Promise<T | undefined> {
    return this.snapshot()[0];
  }

  async toArray(): Promise<T[]> {
    return [...this.snapshot()];
  }

  async sortBy(field: keyof T & string): Promise<T[]> {
    return [...this.snapshot()].sort((left, right) => compareValues(left[field], right[field]));
  }

  filter(nextPredicate: (record: T) => boolean): MockCollection<T> {
    return new MockCollection(this.source, (record) => this.predicate(record) && nextPredicate(record));
  }
}

class MockWhereCollection<T extends RecordType> extends MockCollection<T> {
  constructor(
    source: T[],
    private readonly field: keyof T & string,
    predicate: (record: T) => boolean = () => true,
  ) {
    super(source, predicate);
  }

  equals(value: unknown): MockCollection<T> {
    return new MockCollection(this.source, (record) => this.predicate(record) && record[this.field] === value);
  }
}

class MockTable<T extends RecordType> {
  private readonly records: T[] = [];

  constructor(private readonly keyField: keyof T & string) {}

  async put(record: T): Promise<unknown> {
    const key = record[this.keyField];
    const existingIndex = this.records.findIndex((item) => item[this.keyField] === key);

    if (existingIndex >= 0) {
      this.records[existingIndex] = { ...this.records[existingIndex], ...record };
    } else {
      this.records.push({ ...record });
    }

    return key;
  }

  async add(record: T): Promise<unknown> {
    return this.put(record);
  }

  async update(key: unknown, changes: Partial<T>): Promise<number> {
    const existingIndex = this.records.findIndex((item) => item[this.keyField] === key);

    if (existingIndex === -1) {
      return 0;
    }

    this.records[existingIndex] = { ...this.records[existingIndex], ...changes };
    return 1;
  }

  async get(key: unknown): Promise<T | undefined> {
    return this.records.find((record) => record[this.keyField] === key);
  }

  where(field: keyof T & string): MockWhereCollection<T> {
    return new MockWhereCollection(this.records, field);
  }

  filter(predicate: (record: T) => boolean): MockCollection<T> {
    return new MockCollection(this.records, predicate);
  }

  async toArray(): Promise<T[]> {
    return [...this.records];
  }

  clear(): void {
    this.records.length = 0;
  }
}

class MockDexie {
  users = new MockTable<RecordType>('id');
  messages = new MockTable<RecordType>('id');
  moodEntries = new MockTable<RecordType>('id');
  jigsawProgress = new MockTable<RecordType>('uid');
  syncQueue = new MockTable<RecordType>('id');

  version(_n: number) {
    return { stores: () => {} };
  }

  async open(): Promise<void> {
    return undefined;
  }

  async delete(): Promise<void> {
    this.users.clear();
    this.messages.clear();
    this.moodEntries.clear();
    this.jigsawProgress.clear();
    this.syncQueue.clear();
  }
}

export default MockDexie;
export { MockDexie as Dexie };
