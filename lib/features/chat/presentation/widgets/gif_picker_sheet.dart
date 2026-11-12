import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

class GifPickerSheet extends StatefulWidget {
  const GifPickerSheet({super.key, required this.onGifSelected});

  final ValueChanged<String> onGifSelected;

  @override
  State<GifPickerSheet> createState() => _GifPickerSheetState();
}

class _GifPickerSheetState extends State<GifPickerSheet> {
  final _searchController = TextEditingController();
  List<String> _gifs = [];
  bool _isLoading = false;
  String _selectedCategory = 'Thịnh hành';

  static const List<String> _categories = [
    'Thịnh hành',
    'Haha',
    'Thả tim',
    'Vỗ tay',
    'Khóc',
    'Mèo cute',
    'Chill',
    'Chúc mừng',
  ];

  // Danh sách GIF chất lượng cao có sẵn (offline/fallback siêu tốc không sợ lỗi mạng)
  static const Map<String, List<String>> _curatedGifs = {
    'Thịnh hành': [
      'https://media.giphy.com/media/3oEjI6SIIHBdRxXI40/giphy.gif',
      'https://media.giphy.com/media/l0MYt5jPR6QX5pnqM/giphy.gif',
      'https://media.giphy.com/media/26AHONQ79FdWZhAI0/giphy.gif',
      'https://media.giphy.com/media/5GoVLqeAOo6PK/giphy.gif',
      'https://media.giphy.com/media/xT9IgG50Fb7Mi0prBC/giphy.gif',
      'https://media.giphy.com/media/artj92V8o75VPL7AeQ/giphy.gif',
      'https://media.giphy.com/media/ibolLe3mOqHE3PQTtk/giphy.gif',
      'https://media.giphy.com/media/l41lI4bYmcsPJX9Go/giphy.gif',
    ],
    'Haha': [
      'https://media.giphy.com/media/10JhviFuU2gWD6/giphy.gif',
      'https://media.giphy.com/media/ZqlvCTNHpqrio/giphy.gif',
      'https://media.giphy.com/media/Q7ozWVYCR0nyW2rvPW/giphy.gif',
      'https://media.giphy.com/media/xr9AQyxLtjlxS/giphy.gif',
      'https://media.giphy.com/media/bC9czlgCMtw4cj8RgH/giphy.gif',
    ],
    'Thả tim': [
      'https://media.giphy.com/media/26FLdm964upN2ZYTVc/giphy.gif',
      'https://media.giphy.com/media/3oriO04qxVReM5rJEA/giphy.gif',
      'https://media.giphy.com/media/l4pTdcifPZLpDjL1e/giphy.gif',
      'https://media.giphy.com/media/M90mJvfWfd5mbUuFUh/giphy.gif',
      'https://media.giphy.com/media/R6gVNROjBy4UM/giphy.gif',
    ],
    'Vỗ tay': [
      'https://media.giphy.com/media/7rj2ZgttvgomY/giphy.gif',
      'https://media.giphy.com/media/BPJmthQ3YRwD6QqcVD/giphy.gif',
      'https://media.giphy.com/media/g9582DNuQppxC/giphy.gif',
      'https://media.giphy.com/media/fnK0jeA8vIh2QLq3IZ/giphy.gif',
    ],
    'Khóc': [
      'https://media.giphy.com/media/d2lcHJTG5Tscg/giphy.gif',
      'https://media.giphy.com/media/L95W4wv8nnb9K/giphy.gif',
      'https://media.giphy.com/media/OPU6wzx8JrHna/giphy.gif',
      'https://media.giphy.com/media/3o6wrvdHFbwBrUFenu/giphy.gif',
    ],
    'Mèo cute': [
      'https://media.giphy.com/media/JIX9t2j0ZTN9S/giphy.gif',
      'https://media.giphy.com/media/mlvseq9yvZhba/giphy.gif',
      'https://media.giphy.com/media/BzyTuYCmvSORqs1ABM/giphy.gif',
      'https://media.giphy.com/media/vFKqnCdLPNOKc/giphy.gif',
      'https://media.giphy.com/media/C9x8gX02SnMIoAClXA/giphy.gif',
    ],
    'Chill': [
      'https://media.giphy.com/media/ule4akeXnY9fb4xFWU/giphy.gif',
      'https://media.giphy.com/media/jpbnoe3UIa8TU8LM13/giphy.gif',
      'https://media.giphy.com/media/QMHoU66sBXCAHonWVg/giphy.gif',
    ],
    'Chúc mừng': [
      'https://media.giphy.com/media/3oz8xAFtqoOUUrsh7W/giphy.gif',
      'https://media.giphy.com/media/Is1O1TWV0LEJi/giphy.gif',
      'https://media.giphy.com/media/g9582DNuQppxC/giphy.gif',
    ],
  };

  @override
  void initState() {
    super.initState();
    _gifs = _curatedGifs[_selectedCategory] ?? [];
  }

  Future<void> _searchGifs(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _gifs = _curatedGifs[_selectedCategory] ?? [];
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Tìm kiếm trực tiếp qua GIPHY Public API
      final dio = Dio();
      final resp = await dio.get<Map<String, dynamic>>(
        'https://api.giphy.com/v1/gifs/search',
        queryParameters: {
          'api_key': 'dc6zaTOxFJmzC', // GIPHY public testing key
          'q': trimmed,
          'limit': 24,
          'rating': 'g',
        },
      );

      final dataList = resp.data?['data'];
      final urls = <String>[];
      if (dataList is List) {
        for (final item in dataList) {
          if (item is Map) {
            final images = item['images'];
            final fixedWidth = images?['fixed_width']?['url'];
            if (fixedWidth is String && fixedWidth.isNotEmpty) {
              urls.add(fixedWidth);
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _gifs = urls.isNotEmpty
              ? urls
              : (_curatedGifs[_selectedCategory] ?? []);
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _gifs = _curatedGifs[_selectedCategory] ?? [];
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);

    return SafeArea(
      child: SizedBox(
        height: mediaQuery.size.height * 0.52,
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.gif_box_rounded,
                    color: Colors.purple,
                    size: 28,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Tìm kiếm GIF',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Ô tìm kiếm GIF
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: TextField(
                controller: _searchController,
                onSubmitted: _searchGifs,
                decoration: InputDecoration(
                  hintText: 'Tìm kiếm GIF động (ví dụ: cat, haha, dance…)…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                    onPressed: () => _searchGifs(_searchController.text),
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),

            // Thanh danh mục nhanh
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                itemCount: _categories.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final cat = _categories[index];
                  final isSelected = cat == _selectedCategory;
                  return ChoiceChip(
                    label: Text(cat, style: const TextStyle(fontSize: 12)),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedCategory = cat;
                          _searchController.clear();
                          _gifs = _curatedGifs[cat] ?? [];
                        });
                      }
                    },
                  );
                },
              ),
            ),

            const Divider(height: 1),

            // Lưới hiển thị GIF
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _gifs.isEmpty
                  ? const Center(child: Text('Không tìm thấy GIF nào.'))
                  : GridView.builder(
                      padding: const EdgeInsets.all(8),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            childAspectRatio: 1.3,
                          ),
                      itemCount: _gifs.length,
                      itemBuilder: (context, index) {
                        final gifUrl = _gifs[index];
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            onTap: () {
                              widget.onGifSelected(gifUrl);
                              Navigator.of(context).pop();
                            },
                            child: Image.network(
                              gifUrl,
                              fit: BoxFit.cover,
                              loadingBuilder:
                                  (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Container(
                                      color: theme
                                          .colorScheme
                                          .surfaceContainerHighest,
                                      child: const Center(
                                        child: SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                              errorBuilder: (_, _, _) => Container(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                child: const Icon(
                                  Icons.broken_image,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
