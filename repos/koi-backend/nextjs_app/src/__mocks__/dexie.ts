class MockTable {
  where() { return this; }
  equals() { return this; }
  first() { return Promise.resolve(undefined); }
  add() { return Promise.resolve(1); }
  update() { return Promise.resolve(1); }
}

class MockDexie {
  users = new MockTable();
  messages = new MockTable();
  version(_n: number) {
    return { stores: () => {} };
  }
}

export default MockDexie;
export { MockDexie as Dexie };
