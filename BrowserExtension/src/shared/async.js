export function settleWithin(operation, timeoutMilliseconds) {
  return new Promise((resolve) => {
    let settled = false;
    const finish = (result) => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timeout);
      resolve(result);
    };
    const timeout = setTimeout(
      () => finish({ status: "timedOut" }),
      timeoutMilliseconds,
    );

    Promise.resolve()
      .then(operation)
      .then(
        (value) => finish({ status: "fulfilled", value }),
        () => finish({ status: "rejected" }),
      );
  });
}
