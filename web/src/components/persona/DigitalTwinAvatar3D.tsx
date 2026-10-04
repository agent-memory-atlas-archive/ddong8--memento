"use client";

import { useEffect, useRef, useState } from "react";
import * as THREE from "three";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";

export type PersonaDimension = "brain" | "communication" | "tech" | "execution" | "all";

interface DigitalTwinAvatar3DProps {
  activeDimension: PersonaDimension;
  onSelectDimension: (dim: PersonaDimension) => void;
  ruleStats?: {
    ironLaws: number;
    communication: number;
    tech: number;
    execution: number;
  };
  className?: string;
}

export default function DigitalTwinAvatar3D({
  activeDimension,
  onSelectDimension,
  ruleStats = { ironLaws: 6, communication: 3, tech: 8, execution: 5 },
  className = "",
}: DigitalTwinAvatar3DProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [hoveredNode, setHoveredNode] = useState<PersonaDimension | null>(null);
  const [isRotating, setIsRotating] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [currentActionName, setCurrentActionName] = useState<"idle" | "agree">("idle");
  const [hologramMode, setHologramMode] = useState<"realistic" | "xray">("realistic");

  // Screen anchor points for HUD leader lines (projected from 3D bones)
  const [hudAnchors, setHudAnchors] = useState<Record<string, { x: number; y: number; visible: boolean }>>({
    brain: { x: 0, y: 0, visible: false },
    communication: { x: 0, y: 0, visible: false },
    tech: { x: 0, y: 0, visible: false },
    execution: { x: 0, y: 0, visible: false },
  });

  // Action references
  const mixerRef = useRef<THREE.AnimationMixer | null>(null);
  const actionsRef = useRef<Record<string, THREE.AnimationAction>>({});
  const realAvatarRef = useRef<THREE.Group | null>(null);
  const bonesMapRef = useRef<Record<string, THREE.Object3D>>({});
  const cameraRef = useRef<THREE.PerspectiveCamera | null>(null);
  const rendererRef = useRef<THREE.WebGLRenderer | null>(null);
  const nodesRef = useRef<Record<string, THREE.Mesh>>({});

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    const width = container.clientWidth || 600;
    const height = container.clientHeight || 640;

    // 1. Scene & Camera Setup
    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(40, width / height, 0.1, 100);
    camera.position.set(0, 1.35, 3.2);
    cameraRef.current = camera;

    // 2. WebGL Renderer
    const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
    renderer.setSize(width, height);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.35;
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    rendererRef.current = renderer;

    container.appendChild(renderer.domElement);

    // 3. Studio Lighting for Real Human Skin & Cyber Atmosphere
    const ambientLight = new THREE.AmbientLight(0xffffff, 1.1);
    scene.add(ambientLight);

    // Key front light
    const keyLight = new THREE.DirectionalLight(0xfff5ea, 1.8);
    keyLight.position.set(1.5, 3.2, 3);
    keyLight.castShadow = true;
    scene.add(keyLight);

    // Fill rim light (Violet Cyberpunk)
    const rimLightPurple = new THREE.PointLight(0xa855f7, 3.2, 10);
    rimLightPurple.position.set(-2.5, 2.5, -1.5);
    scene.add(rimLightPurple);

    // Cyan Fill Light
    const fillLightCyan = new THREE.PointLight(0x06b6d4, 2.2, 8);
    fillLightCyan.position.set(2.2, 1.0, 1.8);
    scene.add(fillLightCyan);

    // Soft Bottom Up-light
    const bottomLight = new THREE.PointLight(0x3b82f6, 1.2, 5);
    bottomLight.position.set(0, -1, 1.5);
    scene.add(bottomLight);

    // Avatar Root Group
    const avatarGroup = new THREE.Group();
    avatarGroup.position.set(0, -0.65, 0);
    scene.add(avatarGroup);

    // Surrounding Cyber Floor Disc
    const discGeo = new THREE.RingGeometry(0.7, 1.6, 64);
    const discMat = new THREE.MeshBasicMaterial({
      color: 0x8b5cf6,
      transparent: true,
      opacity: 0.18,
      side: THREE.DoubleSide,
    });
    const disc = new THREE.Mesh(discGeo, discMat);
    disc.rotation.x = -Math.PI / 2;
    disc.position.y = 0.01;
    avatarGroup.add(disc);

    // Ambient floating particles
    const particleCount = 450;
    const particleGeo = new THREE.BufferGeometry();
    const particlePositions = new Float32Array(particleCount * 3);
    for (let i = 0; i < particleCount * 3; i += 3) {
      particlePositions[i] = (Math.random() - 0.5) * 3.5;
      particlePositions[i + 1] = Math.random() * 2.8;
      particlePositions[i + 2] = (Math.random() - 0.5) * 3.5;
    }
    particleGeo.setAttribute("position", new THREE.BufferAttribute(particlePositions, 3));
    const particleMat = new THREE.PointsMaterial({
      color: 0xa855f7,
      size: 0.024,
      transparent: true,
      opacity: 0.55,
      blending: THREE.AdditiveBlending,
    });
    const particles = new THREE.Points(particleGeo, particleMat);
    avatarGroup.add(particles);

    // Interactive Organ Glow Orbs
    const nodeGlowMats = {
      brain: new THREE.MeshStandardMaterial({
        color: 0xa855f7,
        emissive: 0xa855f7,
        emissiveIntensity: 2.2,
        roughness: 0.1,
      }),
      communication: new THREE.MeshStandardMaterial({
        color: 0x06b6d4,
        emissive: 0x06b6d4,
        emissiveIntensity: 2.2,
        roughness: 0.1,
      }),
      tech: new THREE.MeshStandardMaterial({
        color: 0xf59e0b,
        emissive: 0xf59e0b,
        emissiveIntensity: 2.2,
        roughness: 0.1,
      }),
      execution: new THREE.MeshStandardMaterial({
        color: 0x10b981,
        emissive: 0x10b981,
        emissiveIntensity: 2.2,
        roughness: 0.1,
      }),
    };

    // 4 Core Anchors attached to humanoid body
    const brainNode = new THREE.Mesh(new THREE.SphereGeometry(0.065, 16, 16), nodeGlowMats.brain);
    brainNode.userData = { dimension: "brain" };
    avatarGroup.add(brainNode);
    nodesRef.current.brain = brainNode;

    const commNode = new THREE.Mesh(new THREE.SphereGeometry(0.045, 16, 16), nodeGlowMats.communication);
    commNode.userData = { dimension: "communication" };
    avatarGroup.add(commNode);
    nodesRef.current.communication = commNode;

    const techNode = new THREE.Mesh(new THREE.OctahedronGeometry(0.075, 1), nodeGlowMats.tech);
    techNode.userData = { dimension: "tech" };
    avatarGroup.add(techNode);
    nodesRef.current.tech = techNode;

    const execNode = new THREE.Mesh(new THREE.SphereGeometry(0.055, 16, 16), nodeGlowMats.execution);
    execNode.userData = { dimension: "execution" };
    avatarGroup.add(execNode);
    nodesRef.current.execution = execNode;

    // Default positions before bone rigging loads
    brainNode.position.set(0, 1.76, 0.1);
    commNode.position.set(0, 1.54, 0.08);
    techNode.position.set(0, 1.34, 0.12);
    execNode.position.set(0.42, 0.95, 0.15);

    // 4. Load Real-Human Avatar & Animation
    const loader = new GLTFLoader();

    Promise.all([
      loader.loadAsync("/models/avatar_real.glb").catch(() => null),
      loader.loadAsync("/models/human.glb").catch(() => null),
    ]).then(([realGltf, animGltf]) => {
      setIsLoading(false);

      if (realGltf && realGltf.scene) {
        const model = realGltf.scene;
        model.scale.set(1.05, 1.05, 1.05);
        avatarGroup.add(model);
        realAvatarRef.current = model;

        // Traverse to find bones and enhance materials
        const bones: Record<string, THREE.Object3D> = {};
        model.traverse((child) => {
          if (child instanceof THREE.Bone) {
            bones[child.name] = child;
          }
          if (child instanceof THREE.Mesh) {
            child.castShadow = true;
            child.receiveShadow = true;
            if (child.material) {
              child.material.side = THREE.FrontSide;
              if ("roughness" in child.material) {
                child.material.roughness = Math.max(0.3, child.material.roughness * 0.9);
              }
            }
          }
        });
        bonesMapRef.current = bones;

        // Link node meshes to actual bones
        if (bones.Head) {
          bones.Head.add(brainNode);
          brainNode.position.set(0, 0.12, 0.08);
        }
        if (bones.Neck) {
          bones.Neck.add(commNode);
          commNode.position.set(0, 0.04, 0.1);
        }
        if (bones.Spine2) {
          bones.Spine2.add(techNode);
          techNode.position.set(0, 0.12, 0.12);
        }
        if (bones.RightHand) {
          bones.RightHand.add(execNode);
          execNode.position.set(0, 0.06, 0.04);
        }

        // Apply Natural Idle Animations from animGltf
        if (animGltf && animGltf.animations && animGltf.animations.length > 0) {
          const mixer = new THREE.AnimationMixer(model);
          mixerRef.current = mixer;

          const idleClip = animGltf.animations.find((a) => a.name.toLowerCase().includes("idle"));
          const agreeClip = animGltf.animations.find((a) => a.name.toLowerCase().includes("agree"));

          if (idleClip) {
            // Clone and sanitize track names from "mixamorig:Bone" to "Bone"
            const clonedIdle = idleClip.clone();
            clonedIdle.tracks.forEach((track) => {
              track.name = track.name.replace(/^mixamorig:/, "");
            });
            const idleAction = mixer.clipAction(clonedIdle);
            idleAction.setEffectiveTimeScale(0.85); // Gentle, lifelike breathing
            idleAction.play();
            actionsRef.current.idle = idleAction;
          }

          if (agreeClip) {
            const clonedAgree = agreeClip.clone();
            clonedAgree.tracks.forEach((track) => {
              track.name = track.name.replace(/^mixamorig:/, "");
            });
            const agreeAction = mixer.clipAction(clonedAgree);
            agreeAction.loop = THREE.LoopOnce;
            agreeAction.clampWhenFinished = false;
            actionsRef.current.agree = agreeAction;
          }
        }
      }
    });

    // 5. Raycasting for organ clicking & mouse interaction
    const raycaster = new THREE.Raycaster();
    const mouse = new THREE.Vector2();
    let isDragging = false;
    let prevMouseX = 0;
    let prevMouseY = 0;

    const getRaycastTargets = () => {
      return Object.values(nodesRef.current).filter(Boolean);
    };

    const handlePointerDown = (e: MouseEvent) => {
      isDragging = true;
      prevMouseX = e.clientX;
      prevMouseY = e.clientY;
    };

    const handlePointerUp = () => {
      isDragging = false;
    };

    const handlePointerMove = (e: MouseEvent) => {
      const rect = container.getBoundingClientRect();
      mouse.x = ((e.clientX - rect.left) / rect.width) * 2 - 1;
      mouse.y = -((e.clientY - rect.top) / rect.height) * 2 + 1;

      if (isDragging) {
        const deltaX = e.clientX - prevMouseX;
        avatarGroup.rotation.y += deltaX * 0.008;
        prevMouseX = e.clientX;
        prevMouseY = e.clientY;
      }

      // Parallax head/spine subtle sway
      if (bonesMapRef.current.Head && !isDragging) {
        bonesMapRef.current.Head.rotation.y = THREE.MathUtils.lerp(
          bonesMapRef.current.Head.rotation.y,
          mouse.x * 0.28,
          0.05
        );
        bonesMapRef.current.Head.rotation.x = THREE.MathUtils.lerp(
          bonesMapRef.current.Head.rotation.x,
          -mouse.y * 0.18,
          0.05
        );
      }

      // Hover detection on nodes
      raycaster.setFromCamera(mouse, camera);
      const intersects = raycaster.intersectObjects(getRaycastTargets());
      if (intersects.length > 0) {
        const hit = intersects[0].object;
        const dim = hit.userData?.dimension as PersonaDimension;
        setHoveredNode(dim || null);
        container.style.cursor = "pointer";
      } else {
        setHoveredNode(null);
        container.style.cursor = isDragging ? "grabbing" : "grab";
      }
    };

    const handlePointerClick = (e: MouseEvent) => {
      const rect = container.getBoundingClientRect();
      mouse.x = ((e.clientX - rect.left) / rect.width) * 2 - 1;
      mouse.y = -((e.clientY - rect.top) / rect.height) * 2 + 1;

      raycaster.setFromCamera(mouse, camera);
      const intersects = raycaster.intersectObjects(getRaycastTargets());
      if (intersects.length > 0) {
        const hit = intersects[0].object;
        const dim = hit.userData?.dimension as PersonaDimension;
        if (dim) {
          onSelectDimension(dim);
        }
      }
    };

    container.addEventListener("mousedown", handlePointerDown);
    window.addEventListener("mouseup", handlePointerUp);
    container.addEventListener("mousemove", handlePointerMove);
    container.addEventListener("click", handlePointerClick);

    // 6. Animation Loop
    let animId: number;
    const clock = new THREE.Clock();
    const tempVec = new THREE.Vector3();

    const animate = () => {
      animId = requestAnimationFrame(animate);
      const delta = clock.getDelta();
      const elapsed = clock.getElapsedTime();

      // Update character animation
      if (mixerRef.current) {
        mixerRef.current.update(delta);
      }

      // Auto rotation if enabled
      if (isRotating) {
        avatarGroup.rotation.y += 0.005;
      }

      // Float ambient particles
      const positions = particleGeo.attributes.position.array as Float32Array;
      for (let i = 1; i < positions.length; i += 3) {
        positions[i] += Math.sin(elapsed * 0.8 + i) * 0.001;
      }
      particleGeo.attributes.position.needsUpdate = true;

      // Pulse organ nodes
      Object.entries(nodesRef.current).forEach(([key, node]) => {
        const isActive = activeDimension === key || activeDimension === "all";
        const isHover = hoveredNode === key;
        const scale = isActive ? 1.35 + Math.sin(elapsed * 5) * 0.15 : isHover ? 1.25 : 0.95;
        node.scale.set(scale, scale, scale);

        if (key === "tech") {
          node.rotation.x = elapsed * 1.5;
          node.rotation.y = elapsed * 2.0;
        }
      });

      // Calculate screen projection for HUD leader lines
      const newAnchors: Record<string, { x: number; y: number; visible: boolean }> = {};
      const rect = container.getBoundingClientRect();

      Object.entries(nodesRef.current).forEach(([key, node]) => {
        node.getWorldPosition(tempVec);
        tempVec.project(camera);

        const x = ((tempVec.x + 1) * rect.width) / 2;
        const y = ((-tempVec.y + 1) * rect.height) / 2;
        const visible = tempVec.z < 1; // within frustum
        newAnchors[key] = { x, y, visible };
      });
      setHudAnchors(newAnchors);

      renderer.render(scene, camera);
    };

    animate();

    // 7. Resize Observer
    const handleResize = () => {
      if (!container || !renderer || !camera) return;
      const newW = container.clientWidth;
      const newH = container.clientHeight;
      camera.aspect = newW / newH;
      camera.updateProjectionMatrix();
      renderer.setSize(newW, newH);
    };

    const resizeObserver = new ResizeObserver(handleResize);
    resizeObserver.observe(container);

    return () => {
      cancelAnimationFrame(animId);
      resizeObserver.disconnect();
      container.removeEventListener("mousedown", handlePointerDown);
      window.removeEventListener("mouseup", handlePointerUp);
      container.removeEventListener("mousemove", handlePointerMove);
      container.removeEventListener("click", handlePointerClick);
      if (renderer.domElement && container.contains(renderer.domElement)) {
        container.removeChild(renderer.domElement);
      }
      renderer.dispose();
    };
  }, [activeDimension, isRotating, onSelectDimension]);

  // Trigger Agree nodding animation
  const triggerAgreeAction = () => {
    const agree = actionsRef.current.agree;
    const idle = actionsRef.current.idle;
    if (agree) {
      agree.reset();
      agree.fadeIn(0.2);
      agree.play();
      setCurrentActionName("agree");
      setTimeout(() => {
        if (idle) idle.fadeIn(0.3);
        setCurrentActionName("idle");
      }, 1800);
    }
  };

  const DIMENSIONS_CONFIG = [
    {
      id: "brain" as const,
      label: "脑核 · 绝对红线",
      color: "#EF4444",
      bgRgba: "rgba(239, 68, 68, 0.15)",
      borderRgba: "rgba(239, 68, 68, 0.4)",
      count: ruleStats.ironLaws,
      tag: "Cognitive Law",
      desc: "不硬编码、先查官方、不回滚、严守铁律",
    },
    {
      id: "communication" as const,
      label: "喉核 · 交互与沟通",
      color: "#06B6D4",
      bgRgba: "rgba(6, 182, 212, 0.15)",
      borderRgba: "rgba(6, 182, 212, 0.4)",
      count: ruleStats.communication,
      tag: "Vocal Tone",
      desc: "始终中文、直给结论、无废话、1)2)3)编号",
    },
    {
      id: "tech" as const,
      label: "心核 · 技术与架构",
      color: "#F59E0B",
      bgRgba: "rgba(245, 158, 11, 0.15)",
      borderRgba: "rgba(245, 158, 11, 0.4)",
      count: ruleStats.tech,
      tag: "Tech Philosophy",
      desc: "高性能流式、容器化K8s、零停机、本地优先",
    },
    {
      id: "execution" as const,
      label: "肢端 · 工作与执行",
      color: "#10B981",
      bgRgba: "rgba(16, 185, 129, 0.15)",
      borderRgba: "rgba(16, 185, 129, 0.4)",
      count: ruleStats.execution,
      tag: "Autonomous Act",
      desc: "自主推进做完、不半途而废、数据校验闭环",
    },
  ];

  return (
    <div
      className={`relative w-full h-full min-h-[580px] rounded-3xl overflow-hidden select-none border border-[var(--aurora-border)] bg-gradient-to-b from-[#0c0d18] via-[#090a12] to-[#05060b] shadow-2xl ${className}`}
    >
      {/* 3D WebGL Canvas */}
      <div ref={containerRef} className="w-full h-full cursor-grab active:cursor-grabbing" />

      {/* Loading Skeleton */}
      {isLoading && (
        <div className="absolute inset-0 bg-[#090a12]/90 backdrop-blur-md flex flex-col items-center justify-center gap-3 z-30 pointer-events-none">
          <div className="w-12 h-12 rounded-2xl border-2 border-transparent border-t-[#A855F7] animate-spin flex items-center justify-center bg-[#A855F7]/10" />
          <div className="text-xs font-mono text-[#A855F7] tracking-wider animate-pulse">
            LOADING REAL-HUMAN DIGITAL TWIN...
          </div>
          <span className="text-[11px] text-[var(--aurora-fg4)]">
            正在载入真实人物骨骼与待机动作资产
          </span>
        </div>
      )}

      {/* Top Holographic Header Bar */}
      <div className="absolute top-4 left-4 right-4 flex items-center justify-between pointer-events-none z-10">
        <div className="flex items-center gap-2.5 bg-black/40 backdrop-blur-md px-3.5 py-1.5 rounded-full border border-white/10 shadow-lg">
          <div className="w-2 h-2 rounded-full bg-[#10B981] animate-ping" />
          <span className="text-[11px] font-mono text-white/90 font-medium tracking-wide">
            REAL HUMAN DIGITAL TWIN · ONLINE
          </span>
        </div>

        <div className="flex items-center gap-2 pointer-events-auto">
          {/* Nod Action Button */}
          <button
            onClick={triggerAgreeAction}
            className="px-2.5 py-1 rounded-xl text-[11px] font-mono font-medium transition-all bg-white/5 border border-white/10 text-white/80 hover:text-white hover:bg-white/15 flex items-center gap-1.5 backdrop-blur-md"
            title="触发点头赞同真人动画"
          >
            <span>点头回应</span>
            {currentActionName === "agree" && <span className="w-1.5 h-1.5 rounded-full bg-[#10B981]" />}
          </button>

          {/* Auto Rotation Toggle */}
          <button
            onClick={() => setIsRotating((v) => !v)}
            className={`px-2.5 py-1 rounded-xl text-[11px] font-mono font-medium transition-all backdrop-blur-md border ${
              isRotating
                ? "bg-[#A855F7]/25 text-[#A855F7] border-[#A855F7]/50"
                : "bg-white/5 text-white/70 border-white/10 hover:bg-white/10"
            }`}
          >
            {isRotating ? "自转中" : "暂停自转"}
          </button>
        </div>
      </div>

      {/* Floating HUD Leader Tags (Screen-Space Projected onto Real Human Body) */}
      {!isLoading && (
        <div className="absolute inset-0 pointer-events-none overflow-hidden z-20">
          {DIMENSIONS_CONFIG.map((dim) => {
            const anchor = hudAnchors[dim.id];
            if (!anchor || !anchor.visible) return null;

            const isSelected = activeDimension === dim.id;
            const isHover = hoveredNode === dim.id;

            // Decide placement (left or right side based on dimension)
            const isLeft = dim.id === "brain" || dim.id === "tech";

            return (
              <div
                key={dim.id}
                className="absolute pointer-events-auto transition-transform duration-200"
                style={{
                  left: anchor.x,
                  top: anchor.y,
                  transform: isLeft
                    ? "translate(-105%, -50%)"
                    : "translate(15%, -50%)",
                }}
              >
                <div
                  onClick={() => onSelectDimension(dim.id)}
                  className={`group cursor-pointer px-3 py-2 rounded-2xl backdrop-blur-xl border transition-all duration-300 flex items-center gap-2.5 shadow-xl ${
                    isSelected
                      ? "scale-105 shadow-2xl ring-1"
                      : "opacity-85 hover:opacity-100 hover:scale-102"
                  }`}
                  style={{
                    backgroundColor: isSelected ? dim.bgRgba : "rgba(15, 17, 26, 0.75)",
                    borderColor: isSelected ? dim.color : dim.borderRgba,
                    boxShadow: isSelected ? `0 8px 24px -4px ${dim.color}40` : undefined,
                  }}
                >
                  <div
                    className="w-2.5 h-2.5 rounded-full shrink-0 shadow-xs"
                    style={{ backgroundColor: dim.color }}
                  />
                  <div className="flex flex-col text-left">
                    <div className="flex items-center gap-1.5">
                      <span className="text-xs font-bold text-white tracking-tight">
                        {dim.label}
                      </span>
                      <span
                        className="text-[10px] font-mono px-1.5 py-0.2 rounded-full font-bold"
                        style={{ backgroundColor: `${dim.color}25`, color: dim.color }}
                      >
                        {dim.count}
                      </span>
                    </div>
                    <span className="text-[10px] text-white/50 truncate max-w-[130px]">
                      {dim.desc}
                    </span>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* Bottom Compact Dimension Selector Pills */}
      <div className="absolute bottom-3 left-3 right-3 flex items-center justify-between gap-1.5 z-20 pointer-events-auto overflow-x-auto scrollbar-none py-1">
        <button
          onClick={() => onSelectDimension("all")}
          className={`px-3 py-1.5 rounded-xl text-xs font-medium transition-all shrink-0 backdrop-blur-md border ${
            activeDimension === "all"
              ? "bg-[#8B5CF6] text-white border-[#8B5CF6] shadow-lg font-semibold"
              : "bg-black/50 text-white/70 border-white/10 hover:text-white hover:bg-black/70"
          }`}
        >
          🌐 全景视野
        </button>

        {DIMENSIONS_CONFIG.map((dim) => {
          const isSelected = activeDimension === dim.id;
          return (
            <button
              key={dim.id}
              onClick={() => onSelectDimension(dim.id)}
              className={`px-2.5 py-1.5 rounded-xl text-xs font-medium transition-all shrink-0 backdrop-blur-md border flex items-center gap-1.5 ${
                isSelected
                  ? "text-white shadow-lg font-semibold scale-102"
                  : "bg-black/50 text-white/70 border-white/10 hover:text-white hover:bg-black/70"
              }`}
              style={{
                backgroundColor: isSelected ? dim.color : undefined,
                borderColor: isSelected ? dim.color : undefined,
              }}
            >
              <span>{dim.label.split(" · ")[0]}</span>
              <span className="text-[10px] px-1 rounded-full bg-black/25">
                {dim.count}
              </span>
            </button>
          );
        })}
      </div>
    </div>
  );
}
