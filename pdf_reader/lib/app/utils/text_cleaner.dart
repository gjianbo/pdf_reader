/// 文本处理工具类
/// 用于清洗 PDF 提取的文本并分句
class TextProcessUtil {
  /// 将 PDF 提取的原始文本转换为适合朗读的句子列表
  static List<String> cleanAndSplit(String rawText) {
    // 1. 去除多余的换行符，把断行的句子连起来
    // 比如： "Hello wor\nld" -> "Hello world"
    // 统一将 \r\n 和 \n 替换为空格
    String cleanText = rawText.replaceAll('\r\n', ' ').replaceAll('\n', ' ');
    
    // 2. 压缩多个空格为一个
    cleanText = cleanText.replaceAll(RegExp(r'\s+'), ' ');

    // 3. 按标点符号分句 (支持中英文)
    // 正则逻辑：查找 . ? ! 。 ？ ！ 后面紧跟空白的地方进行切割
    // 使用 Lookbehind assertions (?<=...) 确保标点符号保留在句子中
    // 注意：Dart 的 RegExp 不完全支持不定长回顾，但这里标点符号长度固定，可以使用
    // 或者简单的 split 后再拼回去。这里使用文档建议的正则。
    // \s+ 匹配标点后的空白
    RegExp splitPattern = RegExp(r'(?<=[.!?;。！？；])\s+');
    
    List<String> sentences = cleanText.split(splitPattern);
    
    // 4. 过滤无效短句，比如只有标点或空格的
    return sentences.where((s) => s.trim().length > 1).toList();
  }
}
