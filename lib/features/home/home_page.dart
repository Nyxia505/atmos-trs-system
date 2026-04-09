import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/data/mock_destinations.dart';
import 'package:atmos_trs_system/models/destination.dart';
import 'package:atmos_trs_system/features/home/widgets/home_header.dart';
import 'package:atmos_trs_system/features/home/widgets/category_chips.dart';
import 'package:atmos_trs_system/features/home/widgets/hero_map_section.dart';
import 'package:atmos_trs_system/features/home/widgets/recent_visits_section.dart';
import 'package:atmos_trs_system/features/home/widgets/qr_help_sheet.dart';
import 'package:atmos_trs_system/widgets/app_search_bar.dart';

/// Breakpoints for responsive layout (match requirements).
class LayoutBreakpoints {
  static const double tablet = 600;
  static const double desktop = 1100;
}

/// Responsive home page: header, search, category chips, hero map, recent visits.
/// Chips and search filter destinations client-side; ready for Firebase later.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _searchController = TextEditingController();
  late List<Destination> _allDestinations;
  int _selectedCategoryIndex = 0;

  @override
  void initState() {
    super.initState();
    _allDestinations = getMockDestinations();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<CategoryChipData> get _categories => CategoryChips.defaultCategories;

  /// Filter value for the selected chip (e.g. "Beach", "Mountain").
  String get _selectedCategoryFilter => _categories[_selectedCategoryIndex].filterValue;

  /// Filter by selected category and search query (client-side).
  List<Destination> get _filteredDestinations {
    final query = _searchController.text.trim().toLowerCase();
    return _allDestinations.where((d) {
      final matchCategory = d.category == _selectedCategoryFilter;
      if (!matchCategory) return false;
      if (query.isEmpty) return true;
      return d.name.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= LayoutBreakpoints.tablet;
        final maxWidth = constraints.maxWidth >= LayoutBreakpoints.desktop
            ? 1100.0
            : constraints.maxWidth;
        return Scaffold(
          backgroundColor: AppTheme.scaffoldBackground,
          body: SafeArea(
            child: Column(
              children: [
                HomeHeader(
                  userName: 'Alex',
                  onQrTap: () => openQrHelp(context),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(bottom: isWide ? 24 : 80),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AppSearchBar(
                              controller: _searchController,
                              onChanged: (_) => setState(() {}),
                              hintText: 'Search destinations...',
                            ),
                            CategoryChips(
                              categories: _categories,
                              selectedIndex: _selectedCategoryIndex,
                              onSelected: (index) =>
                                  setState(() => _selectedCategoryIndex = index),
                            ),
                            const HeroMapSection(homeStyle: true),
                            RecentVisitsSection(
                              destinations: _filteredDestinations,
                              sectionTitle: _filteredDestinations.isEmpty
                                  ? 'No ${_categories[_selectedCategoryIndex].label}'
                                  : 'Recent Visits',
                              cardWidth: _cardWidth(constraints.maxWidth),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  double _cardWidth(double width) {
    if (width >= LayoutBreakpoints.desktop) return 220;
    if (width >= LayoutBreakpoints.tablet) return 200;
    return 180;
  }
}
