/// 家长控制的成人站点域名列表。
///
/// 只做域名级拦截，不能识别所有站点；由用户在隐私设置里主动开启。
const Set<String> kAdultHosts = {
  'absoluporn.com',
  'anyporn.com',
  'bangbros.com',
  'beeg.com',
  'bongacams.com',
  'brazzers.com',
  'camsoda.com',
  'chaturbate.com',
  'eporner.com',
  'gotporn.com',
  'hqporner.com',
  'inporn.com',
  'livejasmin.com',
  'mofos.com',
  'naughtyamerica.com',
  'onlyfans.com',
  'porndig.com',
  'porndoe.com',
  'pornerbros.com',
  'pornhub.com',
  'pornhubpremium.com',
  'pornhubselect.com',
  'pornmaki.com',
  'porntop.com',
  'porntrex.com',
  'porntube.com',
  'realitykings.com',
  'redtube.com',
  'spankbang.com',
  'stripchat.com',
  'tubepornclassic.com',
  'txxx.com',
  'upornia.com',
  'vporn.com',
  'xhamster.com',
  'xhamsterlive.com',
  'xnxx.com',
  'xvideos.com',
  'youporn.com',
};

bool isAdultUrl(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  if (host.isEmpty) return false;
  for (final blocked in kAdultHosts) {
    if (host == blocked || host.endsWith('.$blocked')) return true;
  }
  return false;
}
