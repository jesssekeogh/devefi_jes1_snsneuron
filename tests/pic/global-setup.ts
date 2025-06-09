import { PocketIcServer } from "@dfinity/pic";

module.exports = async function (): Promise<void> {
  const pic = await PocketIcServer.start({
    // showCanisterLogs: true,
  });
  const url = pic.getUrl();

  process.env.PIC_URL = url;
  global.__PIC__ = pic;
};
