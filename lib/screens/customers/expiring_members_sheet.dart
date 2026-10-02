import 'package:flutter/material.dart';
import '../../models/customer.dart';
import '../../services/gym_service.dart';
import '../../services/whatsapp_service.dart';
import '../../services/phone_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_utils.dart';
import '../../widgets/customer_avatar.dart';
import '../../widgets/mark_payment_dialog.dart';
import 'customer_detail_screen.dart';

class ExpiringMembersSheet extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Customer> members;
  final Color accentColor;
  final IconData icon;

  const ExpiringMembersSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.members,
    required this.accentColor,
    required this.icon,
  });

  static void show(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<Customer> members,
    required Color accentColor,
    required IconData icon,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ExpiringMembersSheet(
        title: title,
        subtitle: subtitle,
        members: members,
        accentColor: accentColor,
        icon: icon,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gym = GymService();
    final currency = gym.settings.currencySymbol;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: AppColors.surfaceBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: Column(
            children: [
              // Drag Handle
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.surfaceBorder,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),

              // Header Banner
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: accentColor, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: accentColor.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        '${members.length} Members',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: accentColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(color: AppColors.surfaceBorder, height: 1),

              // Members List
              Expanded(
                child: members.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_outline, size: 52, color: AppColors.paid),
                            const SizedBox(height: 12),
                            Text(
                              'No members in this category',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'All members in this bucket are up to date.',
                              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
                        itemCount: members.length,
                        itemBuilder: (context, index) {
                          final customer = members[index];
                          final expiryDate = gym.getCustomerExpiryDate(customer);
                          final daysLeft = gym.getDaysUntilExpiry(customer);
                          final renewalFee = gym.settings.getPriceForDuration(
                            customer.planType,
                            customer.planDurationMonths,
                          );

                          final String expiryLabel;
                          if (daysLeft < 0) {
                            final d = daysLeft.abs();
                            expiryLabel = 'Expired $d ${d == 1 ? "day" : "days"} ago';
                          } else if (daysLeft == 0) {
                            expiryLabel = 'Expires Today!';
                          } else {
                            expiryLabel = 'Expires in $daysLeft ${daysLeft == 1 ? "day" : "days"}';
                          }

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            color: AppColors.surfaceElevated,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: daysLeft <= 3
                                    ? accentColor.withValues(alpha: 0.4)
                                    : AppColors.surfaceBorder,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                children: [
                                  // Top Row: Avatar, Name, Expiry Pill
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      CustomerAvatar(
                                        imagePath: customer.imagePath,
                                        imageBase64: customer.imageBase64,
                                        name: customer.name,
                                        radius: 22,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              customer.name,
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                             InkWell(
                                               onTap: () {
                                                 PhoneService().makeCall(
                                                   customer.phone,
                                                   context: context,
                                                   memberName: customer.name,
                                                 );
                                               },
                                               borderRadius: BorderRadius.circular(6),
                                               child: Row(
                                                 mainAxisSize: MainAxisSize.min,
                                                 children: [
                                                   Icon(Icons.phone_outlined, size: 12, color: AppColors.primary),
                                                   const SizedBox(width: 4),
                                                   Text(
                                                     customer.phone,
                                                     style: TextStyle(
                                                       fontSize: 12,
                                                       color: AppColors.textSecondary,
                                                     ),
                                                   ),
                                                 ],
                                               ),
                                             ),
                                            const SizedBox(height: 4),
                                            Wrap(
                                              spacing: 6,
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 7,
                                                        vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.surfaceBorder,
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    CustomerPlan.getShortLabel(customer.planType),
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.w600,
                                                      color: AppColors.textSecondary,
                                                    ),
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 7,
                                                        vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: accentColor.withValues(
                                                          alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    expiryLabel,
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.w700,
                                                      color: accentColor,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Renewal Fee
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            'Renewal Fee',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: AppColors.textMuted,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            GymDateUtils.formatCurrency(renewalFee, symbol: currency),
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w800,
                                              color: AppColors.textPrimary,
                                            ),
                                          ),
                                          Text(
                                            GymDateUtils.formatDisplayDate(expiryDate),
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: AppColors.textMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 12),
                                  Divider(color: AppColors.surfaceBorder, height: 1),
                                  const SizedBox(height: 10),

                                  // Action Buttons Row (WhatsApp & Collect Fee)
                                  Row(
                                    children: [
                                      // WhatsApp Reminder Button
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: () {
                                            final msg = WhatsAppService().buildMembershipExpiryMessage(
                                              customer: customer,
                                              expiryDate: expiryDate,
                                              daysLeft: daysLeft,
                                              renewalAmount: renewalFee,
                                              currency: currency,
                                            );
                                            WhatsAppService().openWhatsApp(
                                              phone: customer.phone,
                                              message: msg,
                                              context: context,
                                            );
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.whatsappDark,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 9),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            elevation: 0,
                                          ),
                                          icon: const Icon(Icons.chat_bubble_outline, size: 15),
                                          label: const Text(
                                            'WhatsApp',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),

                                      // Collect Payment Button
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () {
                                            MarkPaymentDialog.showRenewal(
                                              context,
                                              customer: customer,
                                            );
                                          },
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: AppColors.primary,
                                            side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
                                            padding: const EdgeInsets.symmetric(vertical: 9),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                          ),
                                          icon: const Icon(Icons.check_circle_outline, size: 15),
                                          label: const Text(
                                            'Renew',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),

                                      const SizedBox(width: 4),

                                       // Call Member Button
                                       IconButton(
                                         padding: EdgeInsets.zero,
                                         constraints: const BoxConstraints(minWidth: 36,
                                          minHeight: 36),
                                         icon: Icon(Icons.call_rounded, size: 18, color: AppColors.primary),
                                         tooltip: 'Call Member',
                                         onPressed: () {
                                           PhoneService().makeCall(
                                             customer.phone,
                                             context: context,
                                             memberName: customer.name,
                                           );
                                         },
                                       ),

                                       // Member Detail Profile Button
                                       IconButton(
                                         padding: EdgeInsets.zero,
                                         constraints: const BoxConstraints(minWidth: 36,
                                          minHeight: 36),
                                         icon: Icon(Icons.person_outline, size: 18, color: AppColors.textSecondary),
                                         tooltip: 'View Member Profile',
                                         onPressed: () {
                                           Navigator.push(
                                             context,
                                             MaterialPageRoute(
                                               builder: (_) => CustomerDetailScreen(customerId: customer.id),
                                             ),
                                           );
                                         },
                                       ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
