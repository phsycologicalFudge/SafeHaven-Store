import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

import 'package:safehaven/translations/app_localizations.dart';

class AvatarCropScreen extends StatefulWidget {
  const AvatarCropScreen({super.key, required this.imageBytes});

  final Uint8List imageBytes;

  @override
  State<AvatarCropScreen> createState() => _AvatarCropScreenState();
}

class _AvatarCropScreenState extends State<AvatarCropScreen> {
  final CropController _controller = CropController();
  bool _cropping = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Crop(
                controller: _controller,
                image: widget.imageBytes,
                withCircleUi: true,
                baseColor: Colors.black,
                maskColor: Colors.black.withOpacity(0.75),
                onCropped: (bytes) {
                  Navigator.of(context).pop(bytes);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      AppLocalizations.of(context)!.commonCancel,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _cropping
                        ? null
                        : () {
                      setState(() => _cropping = true);
                      _controller.crop();
                    },
                    child: Text(AppLocalizations.of(context)!.commonDone),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}